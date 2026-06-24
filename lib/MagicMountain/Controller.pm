package MagicMountain::Controller;
use Mojo::Base 'Mojolicious::Controller', '-signatures';

my %REFETCH = (
    'prospecting_begin'         => ['prospecting', 'player'],
    'prospecting_push'          => ['prospecting'],
    'prospecting_stop'          => ['prospecting', 'shed', 'player'],
    'market_begin'              => ['market', 'player', 'shed'],
    'market_offer'              => ['market', 'player', 'shed'],
    'market_send_away'          => ['player'],
    'market_accept_counter'     => ['market', 'player', 'shed'],
    'purchase'                  => ['player', 'skills'],
    'end_season'                => [],
);

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
    my $id = $char->getCol('pending_activity_id') or return undef;
    $self->app->prospecting->load;
    my $row = $self->app->prospecting->table->{$id} or return undef;
    return 'prospecting' if $row->{type} eq 'prospecting';
    return 'market'      if $row->{type} eq 'market_visit';
    return undef;
}

sub _render_action ($self, $result, $action_name) {
    my $refetch = $REFETCH{$action_name} // ['player'];
    $self->render(json => {
        %{ $result->{view} },
        csrf_token => $self->csrf_token,
        refetch    => $refetch,
    });
}

1;