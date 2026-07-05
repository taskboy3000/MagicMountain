package MagicMountain::Controller::Sessions;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub login_form ($self) {
    $self->redirect_to('game');
}

sub _normalize_name ($self, $raw) {
    my $name = $raw // '';
    $name =~ s/^\s+|\s+$//g;
    return $name;
}

sub create ($self) {
    my $ip   = $self->tx->remote_address;
    my $body = $self->req->json;
    my $name = $self->_normalize_name($body->{displayName} // '');
    my $rl   = $self->app->rate_limiter;

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless length $name > 0;

    # Account-name rate limit
    if (!$rl->check_name(lc $name)) {
        my $retry_after = $rl->get_name_reset_time(lc $name);
        $self->res->headers->header('Retry-After' => $retry_after);
        return $self->render(json => {
            ok => 0, error => 'Too many attempts for this account',
            retry_after => $retry_after,
        }, status => 429);
    }

    # Check for existing valid session or remember-me cookie (skip if token provided)
    my $auth = $self->app->auth_service;
    my $submitted_token = uc ($body->{token} // '');
    if (!$submitted_token) {
        my $player_id = $self->session('playerId');
        if ($player_id) {
            $self->app->session_store->load;
            my $sess = $self->app->session_store->find_by_player_id($player_id);
            if ($sess) {
                my $existing_acct = $self->app->accounts->get($player_id);
                if ($existing_acct && $existing_acct->getCol('username') eq $name) {
                    $sess->touch;
                    return $self->render(json => { ok => 1, csrf_token => $self->csrf_token, player => { id => $player_id, displayName => $name } });
                }
            }
        }

        # Check for remember-me cookie
        my $remember_data = $self->_read_remember_cookie;
        if ($remember_data && $remember_data->{account_id}) {
            my $remember_acct = $self->app->accounts->get($remember_data->{account_id});
            if ($remember_acct && $remember_acct->getCol('username') eq $name) {
                if (!$remember_acct->getCol('banned') && $auth->verify_remember_token($remember_acct, $remember_data->{token})) {
                    return $self->render(json => $self->_build_session($remember_acct, $ip));
                }
            }
        }
    }

    # Find or create account
    my $account = $self->app->accounts->find_by_username($name);

    if (!$account) {
        # Validate display name for new accounts
        return $self->render(json => { ok => 0, error => 'Display name must be 1-24 characters: letters, numbers, underscores, dashes' }, status => 400)
            unless length $name <= 24 && $name =~ /^[a-zA-Z0-9_-]+$/;

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
        $self->session(mm_new_credentials => {
            token         => $result->{token},
            recovery_code => $result->{recovery_code},
        });
        $resp->{show_credentials} = 1;
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
    if (!(defined $token_hash && length $token_hash > 0)) {
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

sub recover ($self) {
    my $ip   = $self->tx->remote_address;
    my $body = $self->req->json;
    my $name = $self->_normalize_name($body->{displayName} // '');
    my $code = uc ($body->{recoveryCode} // '');

    return $self->render(json => { ok => 0, error => 'displayName required' }, status => 400) unless $name;
    return $self->render(json => { ok => 0, error => 'Recovery code required' }, status => 400) unless $code;

    my $account = $self->app->accounts->find_by_username($name);
    if (!$account) {
        $self->app->audit_log->log('recovery_failed', player_name => $name);
        return $self->render(json => { ok => 0, error => 'Invalid credentials' }, status => 403);
    }

    if ($account->getCol('banned')) {
        $self->app->audit_log->log('recovery_failed',
            player_name => $name, player_id => $account->getCol('id'));
        return $self->render(json => { ok => 0, error => 'Invalid credentials' }, status => 403);
    }

    if (!$self->app->auth_service->verify_recovery_code($account, $code)) {
        $self->app->rate_limiter->record_failure($ip);
        $self->app->rate_limiter->record_name_failure(lc $name);
        $self->app->audit_log->log('recovery_failed',
            player_name => $name, player_id => $account->getCol('id'));
        return $self->render(json => { ok => 0, error => 'Invalid credentials' }, status => 403);
    }

    my $result = $self->app->auth_service->recover_account($account);
    $self->_set_remember_cookie($result->{remember_token}, $account);

    $self->app->rate_limiter->record_success($ip);
    $self->app->rate_limiter->record_name_success(lc $name);

    $self->app->audit_log->log('account_recovered',
        player_id   => $account->getCol('id'),
        player_name => $name,
    );

    my $resp = $self->_build_session($account, $ip);
    $self->session(mm_new_credentials => {
        token         => $result->{token},
        recovery_code => $result->{recovery_code},
    });
    $resp->{show_credentials} = 1;
    return $self->render(json => $resp);
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
    my $value = join '|', $account->getCol('id'), $remember_token;
    $self->signed_cookie(mm_remember => $value, {
        httponly => 1,
        secure   => $self->req->is_secure,
        samesite => 'Lax',
        path     => '/',
        expires  => time + 86400 * 30,
    });
}

sub _read_remember_cookie ($self) {
    my $data = $self->signed_cookie('mm_remember') // '';
    return unless length $data > 0;
    my ($account_id, $token) = split /\|/, $data, 2;
    return unless $account_id && $token;
    return { account_id => $account_id, token => $token };
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

sub token_prompt ($self) {
    my $format = $self->param('_format') // '';
    $self->stash(display_name => $self->param('display_name') // '',
                 admin_email  => $self->app->config->{admin_email});
    if ($format eq 'fragment') {
        $self->render('sessions/token_prompt', layout => undef);
    } else {
        $self->render(json => { ok => 0, error => 'fragment format required' }, status => 400);
    }
}

sub recovery_form ($self) {
    my $format = $self->param('_format') // '';
    $self->stash(display_name => $self->param('display_name') // '',
                 admin_email  => $self->app->config->{admin_email});
    if ($format eq 'fragment') {
        $self->render('sessions/recovery_form', layout => undef);
    } else {
        $self->render(json => { ok => 0, error => 'fragment format required' }, status => 400);
    }
}

sub credentials ($self) {
    my $format = $self->param('_format') // '';
    return $self->render(json => { ok => 0, error => 'fragment format required' }, status => 400)
        unless $format eq 'fragment';
    my $creds = $self->session('mm_new_credentials');
    return $self->render(text => '', status => 204) unless $creds;
    $self->session(mm_new_credentials => undef);
    $self->stash(%$creds);
    $self->render('sessions/credentials', layout => undef);
}

sub destroy ($self) {
    my $player_id = $self->session('playerId');
    if ($player_id) {
        $self->_clear_nav_state($player_id);
        $self->app->session_store->delete_by_player_id($player_id);
        $self->app->audit_log->log('logout', player_id => $player_id);
    }
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
    $self->session(expires => 1);
    $self->redirect_to('game');
}

1;
