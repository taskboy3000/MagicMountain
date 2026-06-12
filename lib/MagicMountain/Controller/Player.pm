package MagicMountain::Controller::Player;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;
    return $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401)
        unless $player_id;
    my $account = $self->app->accounts->get($player_id);
    $self->render(json => {
        ok => 1,
        player => {
            id          => $player_id,
            displayName => $account->getCol('username'),
        }
    });
}

sub destroy ($self) {
    my $player_id = $self->current_player;
    return $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401)
        unless $player_id;

    $self->app->session_store->delete_by_player_id($player_id);
    $self->session(expires => 1);

    my $chars = $self->app->characters;
    my $existing = $chars->find({ account_id => qr/^\Q$player_id\E$/ });
    for my $char (@$existing) {
        $chars->delete($char->getCol('id'));
    }

    $self->app->accounts->delete($player_id);

    $self->app->audit_log->log('account_deleted', player_id => $player_id);

    $self->render(json => { ok => 1 });
}

1;
