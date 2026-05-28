package MagicMountain::Controller::Sessions;
use Mojo::Base 'MagicMountain::Controller', -signatures;

sub loginForm ($self) {
    $self->render('sessions/new');
}

sub create ($self) {
    my $body = $self->req->json;
    my $name = $body->{displayName};

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless $name;

    my $account = $self->app->accounts->find_by_username($name);

    return $self->render(json => { ok => 0, error => 'Account not found' }, status => 400)
        unless $account;

    $self->session(playerId => $account->getCol('id'));

    $self->render(json => {
        ok => 1,
        player => {
            id          => $account->getCol('id'),
            displayName => $account->getCol('username'),
        }
    });
}

sub destroy ($self) {
    $self->session(expires => 1);
    $self->render(json => { ok => 1 });
}

1;
