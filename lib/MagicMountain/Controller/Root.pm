package MagicMountain::Controller::Root;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub index ($self) {
    $self->redirect_to('game');
}

1;
