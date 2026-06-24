package MagicMountain::Controller;
use Mojo::Base 'Mojolicious::Controller', '-signatures';

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

1;