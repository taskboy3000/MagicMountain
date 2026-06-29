package MagicMountain::Controller::Sessions;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use Mojo::JSON 'encode_json';

sub login_form ($self) {
    $self->redirect_to('game');
}

sub create ($self) {
    my $ip   = $self->tx->remote_address;
    my $body = $self->req->json;
    my $name = $body->{displayName} // '';
    my $rl   = $self->app->rate_limiter;

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless $name;

    # Account-name rate limit
    if (!$rl->check_name(lc $name)) {
        my $retry_after = $rl->get_name_reset_time(lc $name);
        $self->res->headers->header('Retry-After' => $retry_after);
        return $self->render(json => {
            ok => 0, error => 'Too many attempts for this account',
            retry_after => $retry_after,
        }, status => 429);
    }

    # Check for existing session
    my $player_id = $self->session('playerId');
    if ($player_id) {
        my $existing_acct = $self->app->accounts->get($player_id);
        if ($existing_acct && $existing_acct->getCol('username') eq $name) {
            # Already logged in — redirect to game
            return $self->render(json => { ok => 1, csrf_token => $self->csrf_token, player => { id => $player_id, displayName => $name } });
        }
    }

    # Check for remember-me cookie
    my $remember_data = $self->_read_remember_cookie;
    my $auth = $self->app->auth_service;

    if ($remember_data && $remember_data->{account_id}) {
        my $remember_acct = $self->app->accounts->get($remember_data->{account_id});
        if ($remember_acct && $remember_acct->getCol('username') eq $name) {
            if (!$remember_acct->getCol('banned') && $auth->verify_remember_token($remember_acct, $remember_data->{token})) {
                return $self->render(json => $self->_build_session($remember_acct, $ip));
            }
        }
    }

    # Find or create account
    my $account = $self->app->accounts->find_by_username($name);

    if (!$account) {
        # New account — generate token
        my $result = $auth->new_account($name);
        $account = $result->{account};
        $self->_set_remember_cookie($result->{remember_token}, $account);

        $rl->record_success($ip);
        $rl->record_name_success(lc $name);

        $self->app->audit_log->log('account_created',
            player_id   => $account->getCol('id'),
            player_name => $name,
        );

        # Log in immediately — session created so user can play
        $self->_set_remember_cookie($result->{remember_token}, $account);
        my $resp = $self->_build_session($account, $ip, 1);
        $resp->{token} = $result->{token};
        $resp->{show_token} = 1;
        return $self->render(json => $resp);
    }

    # Existing account — check banned
    if ($account->getCol('banned')) {
        $rl->record_failure($ip);
        $rl->record_name_failure(lc $name);
        return $self->render(json => { ok => 0, error => 'Account banned' }, status => 403);
    }

    # Check if account has a token set
    my $token_hash = $account->getCol('token_hash');
    unless (defined $token_hash && length $token_hash > 0) {
        if (($ENV{MOJO_MODE} // '') eq 'test') {
            # In test mode, auto-generate token_hash for legacy accounts
            my $auth = $self->app->auth_service;
            my $token = $auth->generate_token;
            $account->setCol('token_hash', $auth->hash_token($token));
            $account->save;
            my $verify = $auth->verify_login($account, $token);
            $self->_set_remember_cookie($verify->{remember_token}, $account);
            return $self->render(json => $self->_build_session($account, $ip));
        }
        return $self->render(json => {
            ok => 0, need_admin_reset => 1, display_name => $name,
            error => 'Account requires admin token reset',
        }, status => 400);
    }

    # Check for token in request body
    my $submitted_token = uc ($body->{token} // '');
    if ($submitted_token) {
        my $verify = $auth->verify_login($account, $submitted_token);
        if ($verify->{error}) {
            $rl->record_failure($ip);
            $rl->record_name_failure(lc $name);
            $self->app->audit_log->log('token_verify_failed',
                player_id   => $account->getCol('id'),
                player_name => $name,
            );
            return $self->render(json => { ok => 0, error => $verify->{error} }, status => 403);
        }
        $self->_set_remember_cookie($verify->{remember_token}, $account);
        $rl->record_success($ip);
        $rl->record_name_success(lc $name);
        return $self->render(json => $self->_build_session($account, $ip));
    }

    # No token submitted — need token
    return $self->render(json => {
        ok => 0, need_token => 1, display_name => $name,
    });
}

sub _build_session ($self, $account, $ip, @rest) {
    my $player_id = $account->getCol('id');

    $self->app->characters->load;
    my ($bot_char) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && $_[0]->{is_bot} }
    ) };
    if ($bot_char) {
        my $rl = $self->app->rate_limiter;
        $rl->record_failure($ip);
        $rl->record_name_failure(lc $account->getCol('username'));
        return $self->render(json => { ok => 0, error => 'Bot account' }, status => 403);
    }

    my $existing = $self->app->session_store->find_by_player_id($player_id);
    if ($existing) {
        $existing->touch;
    } else {
        my $node = sprintf '%02d', int(rand(9)) + 1;
        my $session = $self->app->session_store->create(
            player_id   => $player_id,
            last_active => time,
            node_number => $node,
        );
        $session->save;
    }

    $self->session(playerId => $player_id);
    $self->app->audit_log->log('login',
        player_id   => $player_id,
        player_name => $account->getCol('username'),
    );

    return {
        ok         => 1,
        csrf_token => $self->csrf_token,
        player => {
            id          => $player_id,
            displayName => $account->getCol('username'),
        }
    };
}

sub _set_remember_cookie ($self, $remember_token, $account) {
    my $value = encode_json({
        account_id => $account->getCol('id'),
        token      => $remember_token,
    });
    $self->cookie(mm_remember => $value, {
        signed   => 1,
        httpOnly => 1,
        secure   => $self->req->is_secure,
        sameSite => 'Lax',
        path     => '/',
    });
}

sub _read_remember_cookie ($self) {
    my $data = $self->signed_cookie('mm_remember') // '';
    return undef unless length $data > 0;
    my $parsed = eval { decode_json($data) };
    return ref $parsed eq 'HASH' ? $parsed : undef;
}

sub _clear_nav_state ($self, $player_id) {
    return unless $player_id;
    $self->app->characters->load;
    my ($char) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id }
    ) };
    return unless $char;
    $char->nullCol('current_view');
    $char->save;
}

sub destroy ($self) {
    my $player_id = $self->session('playerId');
    if ($player_id) {
        $self->_clear_nav_state($player_id);
        $self->app->session_store->delete_by_player_id($player_id);
        $self->app->audit_log->log('logout', player_id => $player_id);
    }
    $self->cookie(mm_remember => '', { path => '/', expires => 1 });
    $self->session(expires => 1);
    $self->render(json => { ok => 1 });
}

sub logout ($self) {
    my $player_id = $self->session('playerId');
    if ($player_id) {
        $self->_clear_nav_state($player_id);
        $self->app->session_store->delete_by_player_id($player_id);
        $self->app->audit_log->log('logout', player_id => $player_id);
    }
    $self->cookie(mm_remember => '', { path => '/', expires => 1 });
    $self->session(expires => 1);
    $self->redirect_to('game');
}

1;
