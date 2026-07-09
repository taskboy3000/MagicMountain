package MagicMountain::Controller::Pvp;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $result = $self->app->pvp_service->build_view($char, apply_url => $self->url_for('pvp_apply'));

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(view => $result);
        return $self->render('pvp/panel', layout => undef);
    }

    $self->render(json => { ok => 1, %$result, _self => { actions => $result->{actions} // [] } });
}

sub apply ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $body = $self->req->json or return $self->render(json => { ok => 0, error => 'json body required' }, status => 400);
    my $result = $self->app->pvp_service->apply_pressure(
        $char,
        $body->{target_id}     // '',
        $body->{faction_id}    // '',
        $body->{effect_type}   // '',
    );
    if ($result->{ok}) {
        $self->render(json => $result);
    } else {
        $self->render(json => $result, status => 400);
    }
}

1;
