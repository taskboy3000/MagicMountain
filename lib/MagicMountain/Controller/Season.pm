package MagicMountain::Controller::Season;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use YAML::XS qw(LoadFile);

sub _load_recap_narratives ($self) {
    state $data = LoadFile($self->app->home . '/content/flavor/recap.yml');
    return $data->{recap};
}

sub _build_narrative ($self, $rec, $highlights) {
    my $narratives = $self->_load_recap_narratives;
    my $final_score = $rec->getCol('final_score') // 0;
    my $rank        = $rec->getCol('rank') // 0;
    my $label       = $rec->getCol('season_id') || '';

    my $all_factions = $self->app->factions_data // [];
    my @faction_ids = map { $_->{id} } @$all_factions;
    my $top_faction_name = $highlights->{top_faction} // 'unknown';
    my $standing = $rec->getCol('faction_standing_snapshot') // {};
    my $factions_data = $self->app->factions_data // [];
    my %name_of = map { $_->{id} => $_->{name} } @$factions_data;

    my $standing_count = scalar keys %$standing;
    my @standing_parts;
    for my $fid (sort { ($standing->{$b} // 0) <=> ($standing->{$a} // 0) } keys %$standing) {
        push @standing_parts, sprintf("%s (+%d)", $name_of{$fid} // $fid, $standing->{$fid});
    }
    my $standing_summary = join(', ', @standing_parts);

    my $top_faction_display = $name_of{$top_faction_name} // $top_faction_name;

    my %ctx = (
        season_label          => $label,
        final_score           => $final_score,
        final_scrap           => $rec->getCol('final_scrap') // 0,
        rank                  => $rank,
        total_sales           => $highlights->{total_sales} // 0,
        top_sale_value        => $highlights->{top_sale_value} // 0,
        top_sale_faction      => $name_of{$highlights->{top_sale_faction}} // ($highlights->{top_sale_faction} // 'unknown'),
        evolved_artifacts_sold => $highlights->{evolved_artifacts_sold} // 0,
        clearance_bonus       => $highlights->{clearance_bonus} // 0,
        top_faction           => $top_faction_display,
        top_faction_influence => $highlights->{top_faction_influence} // 0,
        factions_competing    => $highlights->{factions_competing} // 0,
        factions_competing_minus_1 => ($highlights->{factions_competing} // 0) - 1,
        standing_summary      => $standing_summary,
        standing_count        => $standing_count,
    );

    my $pick = sub ($key) {
        my $lines = $narratives->{$key} or return '';
        return $lines->[rand @$lines];
    };

    my $interp = sub ($str) {
        $str =~ s/\{(\w+)\}/ exists $ctx{$1} ? $ctx{$1} : "{$1}" /ge;
        return $str;
    };

    my @parts;

    push @parts, $interp->($pick->('header'));
    push @parts, '';
    push @parts, $interp->($pick->('subtitle'));
    push @parts, $interp->($pick->('disclaimer'));
    push @parts, '';

    # Market Health
    push @parts, $interp->($pick->('market_health_leader'));
    push @parts, $interp->($pick->('faction_dominance'));

    # Random faction events (0-2 per season)
    my @event_types = qw(faction_event_alliance faction_event_war faction_event_frustration faction_event_merger faction_event_stalemate);
    my $event_count = 1 + int(rand(2));
    my @used_pairs;
    for my $ei (1 .. $event_count) {
        my @pool = grep { $_ ne $top_faction_name } @faction_ids;
        next if @pool < 2;
        my @shuffled = sort { rand() <=> rand() } @pool;
        my $a = $shuffled[0];
        my $b = $shuffled[1];
        next if grep { ($_->[0] eq $a && $_->[1] eq $b) || ($_->[0] eq $b && $_->[1] eq $a) } @used_pairs;
        push @used_pairs, [$a, $b];
        $ctx{faction_a} = $name_of{$a} // $a;
        $ctx{faction_b} = $name_of{$b} // $b;
        my $type = $event_types[int(rand(@event_types))];
        push @parts, $interp->($pick->($type));
    }
    delete $ctx{faction_a};
    delete $ctx{faction_b};

    push @parts, $interp->($pick->('market_assessment_dominated'));
    push @parts, '';

    # Agent Impact
    push @parts, $interp->($pick->('agent_impact_header'));
    if ($standing_count > 0) {
        push @parts, $interp->($pick->('agent_influence'));
    }
    push @parts, $interp->($pick->('agent_impact_significant'));
    push @parts, '';

    # Personal
    push @parts, $interp->($pick->('personal_header'));
    push @parts, $interp->($pick->('rank'));
    push @parts, $interp->($pick->('rank_top'));

    if ($ctx{total_sales} > 0) {
        push @parts, $interp->($pick->('total_sales'));
    }
    if ($ctx{top_sale_value} > 0) {
        push @parts, $interp->($pick->('best_sale'));
    }
    if ($ctx{evolved_artifacts_sold} > 0) {
        push @parts, $interp->($pick->('evolved'));
    }
    if ($ctx{clearance_bonus} > 0) {
        push @parts, $interp->($pick->('clearance'));
    }
    push @parts, '';
    push @parts, $interp->($pick->('closing'));

    return join("\n", @parts);
}

sub recap ($self) {
    my $player_id = $self->current_player;
    return $self->rendered(204) unless $player_id;

    my $season_id = $self->param('season_id');
    $self->app->seasons->load;
    $self->app->season_records->load;

    my $season;
    if ($season_id) {
        $self->app->seasons->load;
        $season = $self->app->seasons->get($season_id);
    } else {
        my $archived = $self->app->seasons->find(sub { ($_[0]->{status} // '') eq 'archived' });
        return $self->rendered(204) unless @$archived;
        my @sorted = sort { ($b->getCol('day') // 0) <=> ($a->getCol('day') // 0) } @$archived;
        $season = $sorted[0];
    }
    return $self->rendered(204) unless $season;

    my $recs = $self->app->season_records->find(
        sub { $_[0]->{player_id} eq $player_id && $_[0]->{season_id} eq $season->getCol('id') }
    );
    return $self->rendered(204) unless @$recs;

    my $rec = $recs->[0];
    my $factions = $self->app->factions_data // [];
    my %name_of = map { $_->{id} => $_->{name} } @$factions;
    my %icon_of = map { $_->{id} => $_->{icon} ? '/images/' . $_->{icon} : undef } @$factions;

    my $standing = $rec->getCol('faction_standing_snapshot') // {};
    my $highlights = $rec->getCol('story_highlights') // {};
    my $skills_rec = $rec->getCol('skills_snapshot') // {};
    my @skills_order = qw(prospecting upcycling selling);

    my @standing_rows;
    for my $fid (sort keys %$standing) {
        push @standing_rows, {
            id     => $fid,
            name   => $name_of{$fid} // $fid,
            icon   => $icon_of{$fid},
            value  => $standing->{$fid},
        };
    }

    my $narrative = $self->_build_narrative($rec, $highlights);

    $self->stash(
        season_label       => $season->getCol('label'),
        final_score        => $rec->getCol('final_score'),
        final_scrap        => $rec->getCol('final_scrap'),
        rank               => $rec->getCol('rank'),
        standing_rows      => \@standing_rows,
        skills             => $skills_rec,
        skills_order       => \@skills_order,
        highs                => $highlights,
        top_faction_name   => $name_of{$highlights->{top_faction}} // $highlights->{top_faction} // '—',
        top_faction_influence => $highlights->{top_faction_influence} // 0,
        factions_competing    => $highlights->{factions_competing} // 0,
        clearance_bonus       => $highlights->{clearance_bonus} // 0,
        narrative             => $narrative,
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        return $self->render('season/recap', layout => undef);
    }
    $self->render(json => {
        ok           => 1,
        season_label => $season->getCol('label'),
        final_score  => $rec->getCol('final_score'),
        final_scrap  => $rec->getCol('final_scrap'),
        rank         => $rec->getCol('rank'),
        standing     => $standing,
        highlights   => $highlights,
        narrative    => $narrative,
    });
}

1;
