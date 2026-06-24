package MagicMountain::Controller::Account;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;
    return $self->rendered(204) unless $player_id;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        return $self->render('account/settings', layout => undef);
    }

    $self->render(json => { ok => 1 });
}

1;
