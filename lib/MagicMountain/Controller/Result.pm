package MagicMountain::Controller::Result;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $result = $char->getCol('result');
    unless ($result) {
        return $self->render(text => '', status => 204);
    }
    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(result => $result);
        return $self->render('result/show', layout => undef);
    }
    $self->render(json => { ok => 1, result => $result });
}

sub dismiss ($self) {
    my $char = $self->_require_character or return;
    $char->nullCol('result');
    $char->setCol('current_view', 'home');
    $char->save;
    $self->render(json => { ok => 1, csrf_token => $self->csrf_token });
}

1;
