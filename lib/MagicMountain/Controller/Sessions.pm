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

sub _resolve_remember_me ($self, $name, $auth) {
    my $data = $self->_read_remember_cookie or return;
    my $acct = $self->app->accounts->get($data->{account_id}) or return;
    return unless $acct->getCol('username') eq $name;
    return if $acct->getCol('banned');
    return unless $auth->verify_remember_token($acct, $data->{token});
    return $acct;
}

sub _bot_service_token ($self) {
    my $header = $self->req->headers->header('X-Bot-Service-Token') // '';
    my $expected = $self->app->config->{bot_service_token} // '';
    return $expected ne '' && $header eq $expected;
}

sub create ($self) {
    my $ip   = $self->tx->remote_address;
    my $body = $self->req->json;
    my $name = $self->_normalize_name($body->{displayName} // '');
    my $rl   = $self->app->rate_limiter;
    my $is_bot_svc = $self->_bot_service_token;

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless length $name > 0;

    if (!$is_bot_svc && !$rl->check_name(lc $name)) {
        my $retry_after = $rl->get_name_reset_time(lc $name);
        $self->res->headers->header('Retry-After' => $retry_after);
        return $self->render(json => {
            ok => 0, error => 'Too many attempts for this account',
            retry_after => $retry_after,
        }, status => 429);
    }

    my $auth = $self->app->auth_service;
    my $submitted_token = uc ($body->{token} // '');

    # Early return: existing Mojo session matches
    if (!$submitted_token) {
        my $player_id = $self->session('playerId');
        if ($player_id) {
            $self->app->session_store->load;
            my $sess = $self->app->session_store->find_by_player_id($player_id);
            if ($sess) {
                my $existing_acct = $self->app->accounts->get($player_id);
                if ($existing_acct && $existing_acct->getCol('username') eq $name) {
                    $sess->touch;
                    my %vars = (
                        csrf_token => $self->csrf_token,
                        player     => { id => $player_id, displayName => $name },
                        game_url   => $self->url_for('game'),
                    );
                    return $self->respond_to(
                        json => sub { $self->render(json => { ok => 1, %vars }) },
                    );
                }
            }
        }
    }

    my ($account, $creds, $auto_authenticated);

    # Try remember-me
    if (!$submitted_token) {
        $account = $self->_resolve_remember_me($name, $auth);
        $auto_authenticated = 1 if $account;
    }

    # Resolve account from username
    if (!$account) {
        my $row = $self->app->accounts->find_by_username($name);

        if (!$row) {
            return $self->render(json => { ok => 0, error => 'Display name must be 1-24 characters: letters, numbers, underscores, dashes' }, status => 400)
                unless length $name <= 24 && $name =~ /^[a-zA-Z0-9_-]+$/;

            my $result = $auth->new_account($name);
            $account = $result->{account};
            $creds   = { token => $result->{token}, recovery_code => $result->{recovery_code} };
            $auto_authenticated = 1;

            $rl->record_success($ip);
            $rl->record_name_success(lc $name);

            $self->app->audit_log->log('account_created',
                player_id   => $account->getCol('id'),
                player_name => $name,
            );

        } else {
            return $self->render(json => { ok => 0, error => 'Account banned' }, status => 403)
                if $row->getCol('banned');

            my $token_hash = $row->getCol('token_hash');

            if (!(defined $token_hash && length $token_hash > 0)) {
                if (($ENV{MOJO_MODE} // '') eq 'test') {
                    my $token = $auth->generate_token;
                    $row->setCol('token_hash', $auth->hash_token($token));
                    $row->save;
                    $account = $row;
                    $auto_authenticated = 1;
                } else {
                    return $self->render(json => {
                        ok => 0, need_admin_reset => 1, display_name => $name,
                        error => 'Account requires admin token reset',
                    }, status => 400);
                }

            } elsif ($submitted_token) {
                my $verify = $auth->verify_login($row, $submitted_token);
                if ($verify->{error}) {
                    $rl->record_failure($ip);
                    $rl->record_name_failure(lc $name);
                    $self->app->audit_log->log('token_verify_failed',
                        player_id   => $row->getCol('id'),
                        player_name => $name,
                    );
                    return $self->render(json => { ok => 0, error => $verify->{error} }, status => 403);
                }
                $account = $row;
                $auto_authenticated = 1;
                $rl->record_success($ip);
                $rl->record_name_success(lc $name);

            } else {
                my %vars = (
                    need_token => 1,
                    display_name => $name,
                    token_prompt_url  => $self->url_for('token_prompt')
                        ->query(display_name => $name, _format => 'fragment'),
                    recovery_form_url => $self->url_for('recovery_form')
                        ->query(display_name => $name, _format => 'fragment'),
                    login_url => $self->url_for('login'),
                    game_url  => $self->url_for('game'),
                );
                return $self->respond_to(
                    json => sub { $self->render(json => { ok => 0, %vars }) },
                );
            }
        }
    }

    my $resp = $self->_build_session($account, $ip) or return;

    if ($creds) {
        $self->session(mm_new_credentials => $creds);
        $resp->{show_credentials} = 1;
    }

    return $self->respond_to(
        json => sub { $self->render(json => $resp) },
    );
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

    $self->app->rate_limiter->record_success($ip);
    $self->app->rate_limiter->record_name_success(lc $name);

    $self->app->audit_log->log('account_recovered',
        player_id   => $account->getCol('id'),
        player_name => $name,
    );

    my $resp = $self->_build_session($account, $ip) or return;
    $self->session(mm_new_credentials => {
        token         => $result->{token},
        recovery_code => $result->{recovery_code},
    });
    $resp->{show_credentials} = 1;
    return $self->respond_to(
        json => sub { $self->render(json => $resp) },
    );
}

sub _build_session ($self, $account, $ip, @rest) {
    my $player_id = $account->getCol('id');

    # Bot check (skip for service-token authenticated requests)
    if (!$self->_bot_service_token) {
        $self->app->characters->load;
        my ($bot_char) = @{ $self->app->characters->find(
            sub { $_[0]->{account_id} eq $player_id && $_[0]->{is_bot} }
        ) };
        if ($bot_char) {
            my $rl = $self->app->rate_limiter;
            $rl->record_failure($ip);
            $rl->record_name_failure(lc $account->getCol('username'));
            $self->render(json => { ok => 0, error => 'Bot account' }, status => 403);
            return;
        }
    }

    # Concurrent session cap
    my $max = $self->app->config->{max_concurrent_sessions} // 10;
    if ($max > 0) {
        $self->app->session_store->load;
        my $existing = $self->app->session_store->find_by_player_id($player_id);
        if (!$existing) {
            my $timeout = $self->app->config->{session_timeout_minutes} // 30;
            my $active = $self->app->session_store->active_count($timeout);
            if ($active >= $max) {
                $self->app->log->debug(sprintf(
                    "Session cap hit: %d active >= %d max for %s (%s)",
                    $active, $max, $account->getCol('username'), $player_id,
                ));
                $self->render(json => {
                    ok => 0, error => 'Server at capacity. Try again later.',
                }, status => 503);
                return;
            }
        }
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

    # Refresh remember-me cookie on every session creation
    my $auth = $self->app->auth_service;
    my $new_token = $auth->generate_remember_token;
    my $new_hash = $auth->hash_token($new_token);
    $account->setCol('remember_token_hash', $new_hash);
    $account->save;
    $self->_set_remember_cookie($new_token, $account);

    return {
        ok         => 1,
        csrf_token => $self->csrf_token,
        player => {
            id          => $player_id,
            displayName => $account->getCol('username'),
        },
        game_url            => $self->url_for('game'),
        new_credentials_url => $self->url_for('new_credentials')->query(_format => 'fragment'),
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
