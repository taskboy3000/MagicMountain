package MagicMountain::Model::Season;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'label', 'length', 'day', 'end_of_day_hour', 'status', 'faction_state', 'crier_message', 'crier_snapshot' ];
};

sub finalize ($class, $app) {
    $app->seasons->load;
    my @active = @{ $app->seasons->find(sub { $_[0]->{status} eq 'active' }) };
    die "No active season to end." unless @active;
    my $season = $active[0];
    my $season_id = $season->getCol('id');
    my $label = $season->getCol('label') // 'unknown';

    $app->log->info("Finalizing season: $label ($season_id)");

    $app->characters->load;
    my $chars = $app->characters->find(sub { $_[0]->{season_id} eq $season_id });
    my @sorted = sort { ($b->getCol('score') // 0) <=> ($a->getCol('score') // 0) } @$chars;
    my %rank_of;
    for my $i (0 .. $#sorted) {
        $rank_of{ $sorted[$i]->getCol('id') } = $i + 1;
    }

    $app->disposition->load;

    # Compute faction influence ranking before clearing
    my $faction_state = $season->getCol('faction_state') // {};
    my @faction_rank = sort { $faction_state->{$b}{influence} // 0 <=> $faction_state->{$a}{influence} // 0 } keys %$faction_state;

    # Clearance sale: unsold shed items liquidated at 25%
    $app->shed->load;
    my %clearance;
    for my $sid (keys %{ $app->shed->table }) {
        my $row = $app->shed->table->{$sid};
        next unless $row->{char_id};
        my $cref = $app->characters->table->{$row->{char_id}};
        next unless $cref && $cref->{season_id} eq $season_id;
        $clearance{ $row->{char_id} } += ($row->{decayed_value} // 0);
        delete $app->shed->table->{$sid};
    }
    $app->shed->save;
    my $total_discard = scalar keys %clearance;
    $app->log->info("Discarded $total_discard shed items.");

    # Award clearance before building SeasonRecords
    for my $char (@sorted) {
        my $clr = int(($clearance{ $char->getCol('id') } // 0) * 0.25);
        next unless $clr;
        $char->setCol('scrap', $char->getCol('scrap') + $clr);
        $char->setCol('score', $char->getCol('score') + $clr);
        $char->save;
    }

    for my $char (@sorted) {
        my $char_id    = $char->getCol('id');
        my $player_id  = $char->getCol('account_id');
        my $rank       = $rank_of{$char_id};
        my $final_score = $char->getCol('score') // 0;
        my $final_scrap = $char->getCol('scrap') // 0;

        my $disps  = $app->disposition->find(sub { $_[0]->{player_id} eq $player_id });
        my $highlights = _build_highlights($disps, $final_score);
        $highlights->{top_faction} = $faction_rank[0] if @faction_rank;
        $highlights->{top_faction_influence} = $faction_state->{$faction_rank[0]}{influence} if @faction_rank;
        $highlights->{factions_competing} = scalar @faction_rank;
        my $clr = int(($clearance{ $char_id } // 0) * 0.25);
        $highlights->{clearance_bonus} = $clr if $clr;

        $app->season_records->create(
            season_id                 => $season_id,
            player_id                 => $player_id,
            final_score               => $final_score,
            final_scrap               => $final_scrap,
            rank                      => $rank,
            faction_standing_snapshot  => $char->getCol('standing') // {},
            skills_snapshot           => {
                prospecting => $char->getCol('skill_prospecting') // 0,
                upcycling   => $char->getCol('skill_upcycling') // 0,
                selling     => $char->getCol('skill_selling') // 0,
            },
            story_highlights          => $highlights,
        )->save;
    }

    $app->season_records->load;
    my $saved = $app->season_records->find(sub { $_[0]->{season_id} eq $season_id });
    die sprintf("ERROR: expected %d records, found %d", scalar @sorted, scalar @$saved)
        if scalar @$saved != scalar @sorted;

    for my $char (@$chars) {
        $app->characters->delete($char->getCol('id'));
    }
    $app->log->info("Deleted " . scalar @$chars . " characters.");

    # Write final faction snapshots before clearing
    for my $fid (keys %$faction_state) {
        $app->faction_snapshots->create(
            season_id         => $season_id,
            day               => $season->getCol('day'),
            faction_id        => $fid,
            influence         => $faction_state->{$fid}{influence} // 0,
            artifacts_received => $faction_state->{$fid}{artifacts_received} // 0,
            intake_by_trait   => $faction_state->{$fid}{intake_by_trait} // {},
        )->save;
    }

    $season->nullCol('faction_state');
    $season->nullCol('crier_message');
    $season->nullCol('crier_snapshot');
    $season->setCol('status', 'archived');
    $season->save;

    return { label => $label, character_count => scalar @$chars, season_id => $season_id };
}

sub _build_highlights ($disps, $final_score) {
    my $total_sales = scalar @$disps;
    my $top_value   = 0;
    my $top_faction = '';
    my %factions;
    my $evolved_count = 0;
    for my $d (@$disps) {
        my $v = $d->getCol('value_awarded') // 0;
        $factions{ $d->getCol('faction_id') // '?' }++;
        if ($v > $top_value) {
            $top_value   = $v;
            $top_faction = $d->getCol('faction_id') // '';
        }
        $evolved_count++ if ($d->getCol('artifact_snapshot') // {})->{has_evolved};
    }
    return {
        total_sales            => $total_sales,
        top_sale_value         => $top_value,
        top_sale_faction       => $top_faction,
        factions_sold_to       => [ sort keys %factions ],
        evolved_artifacts_sold => $evolved_count,
    };
}

1;