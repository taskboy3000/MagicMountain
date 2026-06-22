package MagicMountain::Controller::Sessions;
use Mojo::Base 'MagicMountain::Controller', -signatures;

sub login_form ($self) {
    $self->render('sessions/new');
}

sub create ($self) {
    my $ip   = $self->tx->remote_address;
    my $body = $self->req->json;
    my $name = $body->{displayName};
    my $rl   = $self->app->rate_limiter;

    # Account-name rate limit check
    if ($name && !$rl->check_name(lc $name)) {
        my $retry_after = $rl->get_name_reset_time(lc $name);
        $self->res->headers->header('Retry-After' => $retry_after);
        return $self->render(json => {
            ok => 0, error => 'Too many attempts for this account',
            retry_after => $retry_after,
        }, status => 429);
    }

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless $name;

    my $account = $self->app->accounts->find_by_username($name);

    if ($account && $account->getCol('disabled')) {
        $rl->record_failure($ip);
        $rl->record_name_failure(lc $name);
        return $self->render(json => { ok => 0, error => 'Account is disabled' }, status => 403);
    }

    my $is_new = 0;
    if (!$account) {
        $account = $self->app->accounts->create(username => $name);
        $account->save;
        $is_new = 1;
    }

    my $player_id = $account->getCol('id');

    my $existing = $self->app->session_store->find_by_player_id($player_id);
    if ($existing) {
        $existing->touch;
    } else {
        my $session = $self->app->session_store->create(
            player_id   => $player_id,
            last_active => time,
        );
        $session->save;
    }

    $self->session(playerId => $player_id);

    $rl->record_success($ip);
    $rl->record_name_success(lc $name);

    $self->app->audit_log->log('login',
        player_id   => $player_id,
        player_name => $account->getCol('username'),
    );
    if ($is_new) {
        $self->app->audit_log->log('account_created',
            player_id   => $player_id,
            player_name => $account->getCol('username'),
        );
    }

    $self->render(json => {
        ok         => 1,
        csrf_token => $self->csrf_token,
        player => {
            id          => $player_id,
            displayName => $account->getCol('username'),
        }
    });
}

sub destroy ($self) {
    my $player_id = $self->session('playerId');
    if ($player_id) {
        $self->app->session_store->delete_by_player_id($player_id);
        $self->app->audit_log->log('logout', player_id => $player_id);
    }
    $self->session(expires => 1);
    $self->render(json => { ok => 1 });
}

sub logout ($self) {
    my $player_id = $self->session('playerId');
    if ($player_id) {
        $self->app->session_store->delete_by_player_id($player_id);
        $self->app->audit_log->log('logout', player_id => $player_id);
    }
    $self->session(expires => 1);
    $self->redirect_to('login_form');
}

1;
