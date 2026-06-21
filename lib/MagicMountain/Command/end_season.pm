package MagicMountain::Command::end_season;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Finalize the active season, archive records, and clean up';
has usage       => "Usage: $0 end-season\n";

sub run ($self, @args) {
    my $app = $self->app;

    $app->seasons->load;
    my @active = @{ $app->seasons->find(sub { $_[0]->{status} eq 'active' }) };
    unless (@active) {
        say "No active season to end.";
        exit 1;
    }
    my $season = $active[0];
    my $season_id = $season->getCol('id');
    my $label = $season->getCol('label') // 'unknown';

    say "Finalizing season: $label ($season_id)";

    # 1. Compute leaderboard
    $app->characters->load;
    my $chars = $app->characters->find(sub { $_[0]->{season_id} eq $season_id });
    my @sorted = sort { ($b->getCol('score') // 0) <=> ($a->getCol('score') // 0) } @$chars;
    my %rank_of;
    for my $i (0 .. $#sorted) {
        $rank_of{ $sorted[$i]->getCol('id') } = $i + 1;
    }

    say sprintf("  Found %d characters. Computing records...", scalar @sorted);

    # 2. Build SeasonRecords
    $app->disposition->load;
    my @records;
    for my $char (@sorted) {
        my $char_id = $char->getCol('id');
        my $player_id = $char->getCol('account_id');
        my $rank = $rank_of{$char_id};

        my $final_score = $char->getCol('score') // 0;
        my $final_scrap = $char->getCol('scrap') // 0;
        my $standing = $char->getCol('standing') // {};
        my $skills = {
            prospecting => $char->getCol('skill_prospecting') // 0,
            upcycling   => $char->getCol('skill_upcycling') // 0,
            selling     => $char->getCol('skill_selling') // 0,
        };

        my $disps = $app->disposition->find(sub { $_[0]->{player_id} eq $player_id });
        my $highlights = _build_highlights($disps, $final_score);

        my $rec = $app->season_records->create(
            season_id                => $season_id,
            player_id                => $player_id,
            final_score              => $final_score,
            final_scrap              => $final_scrap,
            rank                     => $rank,
            faction_standing_snapshot => $standing,
            skills_snapshot          => $skills,
            story_highlights         => $highlights,
        );
        $rec->save;
        push @records, $rec;
    }

    # 3. Verify all records saved
    $app->season_records->load;
    my $saved = $app->season_records->find(sub { $_[0]->{season_id} eq $season_id });
    if (scalar @$saved != scalar @sorted) {
        say sprintf("  ERROR: expected %d records, found %d. Aborting.", scalar @sorted, scalar @$saved);
        exit 1;
    }
    say sprintf("  Verified %d SeasonRecords stored.", scalar @$saved);

    # 4. Discard ShedItems for this season
    $app->shed->load;
    my $discard = 0;
    for my $sid (keys %{ $app->shed->table }) {
        my $row = $app->shed->table->{$sid};
        next unless $row->{char_id};
        my $cref = $app->characters->table->{$row->{char_id}};
        next unless $cref && $cref->{season_id} eq $season_id;
        delete $app->shed->table->{$sid};
        $discard++;
    }
    $app->shed->save;
    say sprintf("  Discarded %d shed items.", $discard);

    # 5. Delete SeasonalCharacters
    for my $char (@$chars) {
        $app->characters->delete($char->getCol('id'));
    }
    say sprintf("  Deleted %d characters.", scalar @$chars);

    # 6. Clear faction_state
    $season->nullCol('faction_state');
    $season->nullCol('crier_message');
    $season->nullCol('crier_snapshot');

    # 7. Archive the season
    $season->setCol('status', 'archived');
    $season->save;

    say "Season '$label' archived successfully.";
}

sub _build_highlights ($disps, $final_score) {
    my $total_sales = scalar @$disps;
    my $top_value = 0;
    my $top_faction = '';
    my %factions;
    my $evolved_count = 0;
    for my $d (@$disps) {
        my $v = $d->getCol('value_awarded') // 0;
        $factions{ $d->getCol('faction_id') // '?' }++;
        if ($v > $top_value) {
            $top_value = $v;
            $top_faction = $d->getCol('faction_id') // '';
        }
        my $snap = $d->getCol('artifact_snapshot') // {};
        $evolved_count++ if $snap->{has_evolved};
    }
    return {
        total_sales   => $total_sales,
        top_sale_value => $top_value,
        top_sale_faction => $top_faction,
        factions_sold_to => [ sort keys %factions ],
        evolved_artifacts_sold => $evolved_count,
    };
}

1;
