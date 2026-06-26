package MagicMountain::Controller::Season;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::SeasonReport;

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

    my $standing  = $rec->getCol('faction_standing_snapshot') // {};
    my $highlights = $rec->getCol('story_highlights') // {};

    my @standing_rows;
    for my $fid (sort keys %$standing) {
        push @standing_rows, {
            id    => $fid,
            name  => $name_of{$fid} // $fid,
            icon  => $icon_of{$fid},
            value => $standing->{$fid},
        };
    }

    my $report = MagicMountain::SeasonReport->new(
        final_score  => $rec->getCol('final_score') // 0,
        final_scrap  => $rec->getCol('final_scrap') // 0,
        rank         => $rec->getCol('rank') // 0,
        standing     => $standing,
        highlights   => $highlights,
        season_label => $season->getCol('label'),
        factions     => $factions,
        log          => sub ($event) { $self->app->transcript->log_event($event) },
    );
    my $sections = $report->build;

    $self->stash(
        sections      => $sections,
        season_label  => $season->getCol('label'),
        final_score   => $rec->getCol('final_score'),
        final_scrap   => $rec->getCol('final_scrap'),
        rank          => $rec->getCol('rank'),
        standing_rows => \@standing_rows,
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        return $self->render('season/recap', layout => undef);
    }

    my @narrative_parts;
    for my $sec (@$sections) {
        my $tpl = "season/recap/$sec->{id}";
        next unless -e $self->app->home->child("templates/${tpl}.html.ep");
        push @narrative_parts, $sec->{data}{picked_text} // sprintf("[%s]", $sec->{id});
    }

    $self->render(json => {
        ok           => 1,
        season_label => $season->getCol('label'),
        final_score  => $rec->getCol('final_score'),
        final_scrap  => $rec->getCol('final_scrap'),
        rank         => $rec->getCol('rank'),
        standing     => $standing,
        highlights   => $highlights,
        sections     => $sections,
    });
}

1;
