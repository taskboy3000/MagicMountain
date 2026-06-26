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

    my $standing  = $rec->getCol('faction_standing_snapshot') // {};
    my $highlights = $rec->getCol('story_highlights') // {};

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
    my $standing_rows = $report->build_standing_rows;

    $self->stash(
        sections      => $sections,
        season_label  => $season->getCol('label'),
        final_score   => $rec->getCol('final_score'),
        final_scrap   => $rec->getCol('final_scrap'),
        rank          => $rec->getCol('rank'),
        standing_rows => $standing_rows,
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
        sections     => $sections,
    });
}

1;
