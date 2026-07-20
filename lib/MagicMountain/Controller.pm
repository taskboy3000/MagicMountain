package MagicMountain::Controller;
use Mojo::Base 'Mojolicious::Controller', '-signatures';

sub _require_character ($self) {
    my $player_id = $self->current_player;
    return if !$player_id;
    my $season = $self->app->active_season;
    my $season_id = $season ? $season->getCol('id') : undef;

    $self->app->characters->load;
    my ($char) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
    ) };
    if (!$char) {
        $self->render(json => { ok => 0, error => 'No character' }, status => 404);
        return;
    }
    return $char;
}

sub _active_activity_type ($self, $char) {
    my $id = $char->getCol('pending_activity_id');
    return if !$id;
    # All activity types share activities.json, so loading any one model
    # populates the table for all. Load a known-good model to read the row.
    $self->app->prospecting->load;
    my $activity = $self->app->prospecting->get($id) or return;
    my $type     = $activity->getCol('type') or return;
    return 'prospecting' if $type eq 'prospecting';
    return 'market'      if $type eq 'market_visit';
    return 'pawn'        if $type eq 'pawn';
    return;
}

sub _render_action ($self, $result, $action_name) {
    $self->render(json => {
        %{ $result->{view} },
        csrf_token => $self->csrf_token,
    });
}

1;
