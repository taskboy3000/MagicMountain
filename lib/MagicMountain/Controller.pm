package MagicMountain::Controller;
use Mojo::Base 'Mojolicious::Controller', '-signatures';

sub url_for ($self, $target = undef, @args) {
    my $url = $self->SUPER::url_for($target, @args);
    return $url unless defined $target;
    my $base = $self->req->url->base;
    return $url unless $base->path ne '/' && $base->path ne '';
    $url->path($base->path . $url->path);
    return $url;
}

sub _require_character ($self) {
    my $player_id = $self->current_player;
    return unless $player_id;
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
    my $id = $char->getCol('pending_activity_id') or return;
    # All activity types share activities.json, so loading any one model
    # populates the table for all. Load a known-good model to read the row.
    $self->app->prospecting->load;
    my $row = $self->app->prospecting->table->{$id};
    if (!$row && $self->app->can('black_market')) {
        $self->app->black_market->load;
        $row = $self->app->black_market->table->{$id};
    }
    return unless $row;
    return 'prospecting'  if $row->{type} eq 'prospecting';
    return 'market'       if $row->{type} eq 'market_visit';
    return 'black_market' if $row->{type} eq 'black_market';
    return;
}

sub _render_action ($self, $result, $action_name) {
    $self->render(json => {
        %{ $result->{view} },
        csrf_token => $self->csrf_token,
    });
}

1;