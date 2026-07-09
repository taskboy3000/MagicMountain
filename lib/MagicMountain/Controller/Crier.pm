package MagicMountain::Controller::Crier;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player or return $self->redirect_to('login_form');
    my $season = $self->app->active_season;
    return $self->rendered(204) unless $season;

    my $message = $season->getCol('crier_message');

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(message => $message // 'The crier has not yet spoken today.');
        return $self->render('crier/bulletin', layout => undef);
    }

    $self->render(json => { ok => 1, message => $message // '' });
}

1;
