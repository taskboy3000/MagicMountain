package MagicMountain::Controller::Root;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub index ($self) {
    my $player_id = $self->current_player;
    if ($player_id) {
        return $self->redirect_to('game');
    }
    $self->redirect_to('login_form');
}

1;
