package MagicMountain;

use File::Basename;
use File::Find;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Home;
use Mojo::IOLoop;
use Time::HiRes;
use List::Util 'shuffle';

use MagicMountain::Model::Account;
use MagicMountain::Model::AuditLog;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;
use MagicMountain::Model::Session;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Transcript;
use MagicMountain::Model::ArtifactDisposition;
use MagicMountain::Model::SeasonRecord;
use MagicMountain::Model::FactionSnapshot;
use MagicMountain::Maintenance;
use MagicMountain::Activity::Prospecting;
use MagicMountain::ShedManager;
use MagicMountain::Crier;
use MagicMountain::Service::Authentication;
use MagicMountain::RateLimiter;
use MagicMountain::Service::RandomEvents;
use MagicMountain::Service::BotRunner;
use MagicMountain::Service::PvP;
use MagicMountain::Service::Dominance;
use MagicMountain::Model::Pressure;

has configFile => sub ($self) {
    $ENV{MM_CFG_FILE} || $self->home . '/' . $self->moniker . '.yml';
};

has defaultConfig => sub ($self) {
    return {
        secrets                   => [ 'override-me' ],
        session_timeout_minutes   => 60,
        end_of_day_hour           => 0,
        maintenance_window_minutes => 5,
        default_season_length     => 30,
        default_season_label_prefix => 'Season',
        default_daily_turns       => 10,
        default_action_points     => 20,
        rate_limit_max_attempts          => 5,
        rate_limit_max_attempts_per_name => 5,
        rate_limit_window_minutes        => 15,
        rate_limit_block_minutes         => 15,
        rate_limit_cleanup_interval      => 300,
        rate_limit_trusted_proxies       => 0,
        market_trait_saturation_rate    => 0.01,
        market_max_saturation_discount  => 0.50,
        market_post_appetite_penalty    => 0.50,
        market_desperation_bonus        => 1.30,
        market_counter_offers           => 1,
        market_multi_item               => 1,
        faction_max_stars               => 5,
        bots                            => { count => 0 },
        admin_email                     => 'root@localhost',
        bcrypt_cost                     => 10,
        admin_secret                    => 'override-me',
        pvp_enabled                    => 1,
        pvp_max_stack                  => 3,
        pvp_cost_corner_market         => 50,
        pvp_cost_spoil_lead            => 30,
        pvp_cost_outbid                => 75,
        pvp_splash_saturation_floor    => 0.50,
        pvp_splash_standing_loss       => 1,
        pvp_splash_budget_ratio        => 0.80,
        pvp_bot_aggressiveness         => 0.20,
        pvp_pressure_max_age_days      => 7,
        onboarding_skill_unlock_scrap  => 100,
    }
};

has dataDir => sub ($self) {
    $ENV{MM_DATA_DIR} || $self->home . '/data';
};

has accounts => sub ($self) {
    MagicMountain::Model::Account->new(
        file => $self->dataDir . '/accounts.json',
        log => $self->app->log
    );
};

has session_store => sub ($self) {
    MagicMountain::Model::Session->new(
        file => $self->dataDir . '/sessions.json',
        log => $self->app->log
    );
};

has seasons => sub ($self) {
    MagicMountain::Model::Season->new(
        file => $self->dataDir . '/seasons.json',
        log => $self->app->log
    );
};

has characters => sub ($self) {
    MagicMountain::Model::Character->new(
        file => $self->dataDir . '/characters.json',
        log  => $self->app->log,
        app  => $self,
    );
};

has shed => sub ($self) {
    MagicMountain::Model::ShedItem->new(
        file => $self->dataDir . '/shed.json',
        log  => $self->log,
    );
};

has shed_manager => sub ($self) {
    MagicMountain::ShedManager->new(app => $self);
};

has crier => sub ($self) {
    MagicMountain::Crier->new(
        content_file => $self->home . '/content/flavor/crier.yml',
    );
};

has transcript => sub ($self) {
    MagicMountain::Model::Transcript->new(
        file => $self->dataDir . '/transcript.jsonl',
    );
};

has prospecting => sub ($self) {
    my $p = MagicMountain::Activity::Prospecting->new(
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/prospecting.yml',
        log              => $self->log,
    );
    $p->load_content;
    return $p;
};

use MagicMountain::Activity::MarketVisit;

has market => sub ($self) {
    MagicMountain::Activity::MarketVisit->new(
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/factions.yml',
        log              => $self->log,
    )->load_content;
};

has maintenance => sub ($self) {
    my $maint = MagicMountain::Maintenance->new(
        app             => $self,
        end_of_day_hour => $self->config->{end_of_day_hour} // 0,
        on_maintenance  => sub ($maint) {
            my $season = $maint->app->active_season;
            return unless $season;

            if (!$maint->_catching_up) {
                my $bots_cfg = $maint->app->config->{bots} // {};
                if (($bots_cfg->{count} // 0) > 0) {
                    my $bot_transcript = MagicMountain::Model::Transcript->new(
                        file => $maint->app->dataDir . '/transcript_bots.jsonl'
                    );
                    $maint->app->bot_runner->transcript($bot_transcript);

                    my $bot_chars = $maint->app->characters->find(sub {
                        $_[0]->{season_id} eq $season->getCol('id')
                        && $_[0]->{is_bot}
                    });

                    if (@$bot_chars) {
                        srand(join('', unpack('C*', $season->getCol('id') // '')) + $season->getCol('day'));
                        my @shuffled = List::Util::shuffle(@$bot_chars);
                        my $saved_transcript = $maint->app->{transcript};
                        $maint->app->{transcript} = $bot_transcript;
                        for my $bot_char (@shuffled) {
                            eval {
                                $maint->app->bot_runner->run_day($bot_char);
                            };
                            if ($@) {
                                $maint->app->log->warn(sprintf(
                                    "Bot %s daily run failed: %s",
                                    $bot_char->getCol('name') // '?', $@
                                ));
                            }
                        }
                        $maint->app->{transcript} = $saved_transcript;
                    }
                }
            }

            # Clear yesterday's modifiers before drawing new ones
            $season->setCol('daily_modifiers', {});
            $season->setCol('global_event_text', undef);

            my $day    = $season->getCol('day') + 1;
            $maint->app->log->info(sprintf("Maintenance: %s day %d -> %d",
                $season->getCol('label') // '?', $day - 1, $day));
            $season->setCol('day', $day);
            $season->save;

            $maint->app->characters->load;
            my $chars = $maint->app->characters->find(sub { $_[0]->{season_id} eq $season->getCol('id') });
            for my $char (@$chars) {
                my $max = $char->getCol('action_points_max') // $maint->app->config->{default_action_points} // 15;
                $char->setCol('action_points', $max);
                $char->save;
            }

            $maint->app->shed_manager->apply_decay;

            # Market dynamics reset (daily_intake=0, days_since_purchase++)
            my $fs = $season->getCol('faction_state') // {};
            for my $fid (keys %$fs) {
                $fs->{$fid}->{daily_intake} = 0;
                $fs->{$fid}->{days_since_purchase}++;
            }
            $season->setCol('faction_state', $fs);

            # Faction climate calculation
            $self->dominance_service->calculate_climate($season);

            # Global event: draw and apply modifiers
            if ($maint->app->can('random_events')) {
                my $global_event = $maint->app->random_events->draw(
                    pool    => 'global',
                    trigger => 'day_start',
                    context => {
                        season        => $season,
                        faction_state => \%$fs,
                    },
                );
                if ($global_event) {
                    $maint->app->random_events->apply_effects(
                        $global_event, 'global',
                        { season => $season, faction_state => \%$fs },
                    );
                    $season->setCol('global_event_text', $global_event->{text});
                    $maint->app->log->info(
                        sprintf("Global event [%s]: %s", $global_event->{id}, $global_event->{text})
                    );
                }
            }

            # Crier generation (reads global_event_text first)
            my $crier_opts = $maint->_catching_up ? { time_warp => 1 } : {};
            my $msg = $maint->app->crier->generate($season, $crier_opts);
            $season->setCol('crier_message', $msg);
            $season->setCol('crier_snapshot', $season->getCol('faction_state'));

            for my $fid (keys %$fs) {
                $maint->app->faction_snapshots->create(
                    season_id         => $season->getCol('id'),
                    day               => $day,
                    faction_id        => $fid,
                    influence         => $fs->{$fid}{influence} // 0,
                    artifacts_received => $fs->{$fid}{artifacts_received} // 0,
                    intake_by_trait   => $fs->{$fid}{intake_by_trait} // {},
                )->save;
            }

            $season->setCol('faction_state', $fs);

            $maint->app->transcript->log_event({
                type     => 'faction_snapshot',
                day      => $day,
                factions => $season->getCol('faction_state') // {},
                narrative => sprintf("Day %d faction snapshot: %s",
                    $day, $msg // 'no message'),
            }) if $maint->app->can('transcript') && $maint->app->transcript;

            $season->setCol('last_maintenance', CORE::time);
            $season->save;

            my $length = $season->getCol('length');
            if ($day > $length) {
                $maint->app->log->warn(sprintf(
                    "Season '%s' day %d exceeds configured length %d",
                    $season->getCol('label'), $day, $length
                ));
            }
        },
    );
    $maint->next_run;
    return $maint;
};

has audit_log => sub ($self) {
    MagicMountain::Model::AuditLog->new(
        file => $self->dataDir . '/audit.jsonl',
    );
};

has disposition => sub ($self) {
    MagicMountain::Model::ArtifactDisposition->new(
        file => $self->dataDir . '/dispositions.json',
        log  => $self->log,
    );
};

has season_records => sub ($self) {
    MagicMountain::Model::SeasonRecord->new(
        file => $self->dataDir . '/season_records.json',
        log  => $self->log,
    );
};

has faction_snapshots => sub ($self) {
    MagicMountain::Model::FactionSnapshot->new(
        file => $self->dataDir . '/faction_snapshots.json',
        log  => $self->log,
    );
};

has rate_limiter => sub ($self) {
    MagicMountain::RateLimiter->new(
        max_attempts          => $self->config->{rate_limit_max_attempts},
        max_attempts_per_name => $self->config->{rate_limit_max_attempts_per_name},
        window_minutes        => $self->config->{rate_limit_window_minutes},
        block_minutes         => $self->config->{rate_limit_block_minutes},
    );
};

has random_events => sub ($self) {
    MagicMountain::Service::RandomEvents->new(app => $self);
};

has auth_service => sub ($self) {
    MagicMountain::Service::Authentication->new(app => $self);
};

has bot_runner => sub ($self) {
    MagicMountain::Service::BotRunner->new(app => $self);
};

has season_manager => sub ($self) {
    MagicMountain::Service::SeasonManager->new(app => $self);
};

has pressures => sub ($self) {
    MagicMountain::Model::Pressure->new(
        file => $self->dataDir . '/pressures.json',
        log  => $self->log,
    );
};

has pvp_service => sub ($self) {
    MagicMountain::Service::PvP->new(app => $self);
};

has dominance_service => sub ($self) {
    MagicMountain::Service::Dominance->new(app => $self);
};

sub startup ($self) {
    $self->log->debug(sprintf("[%s] startup: mode=%s",
                        $self->moniker, $self->mode
                    )
    );
    $self->log->debug("Attempting to load config from: " . $self->configFile);
    $self->plugin('NotYAMLConfig' => {
            file => $self->configFile,
            default => $self->defaultConfig
        }
    );

    push @{ $self->commands->namespaces }, 'MagicMountain::Command';
    # Seed RNG for deterministic walkthrough runs
    srand($ENV{MM_RAND_SEED}) if defined $ENV{MM_RAND_SEED};

    # Test mode: force feature flags on, disable rate limiting
    if ($self->mode eq 'test') {
        $self->config->{market_counter_offers} = 1;
        $self->config->{market_multi_item}     = 1;
        $self->config->{rate_limit_max_attempts}          = 999999;
        $self->config->{rate_limit_max_attempts_per_name} = 999999;
    }

    my $local_cfg = $self->home . '/magic_mountain.local.yml';
    if (!-e $local_cfg && -w $self->home && ($self->config->{secrets} // [])->[0] =~ /^(override-me|surewhynot)$/) {
        my $random = unpack('H*', do { open my $fh, '<', '/dev/urandom'; my $b; read $fh, $b, 32; close $fh; $b });
        YAML::XS::DumpFile($local_cfg, {
            secrets      => [ $random ],
            admin_secret => $random,
        });
        $self->log->info("Generated $local_cfg with random secret");
    }
    if (-e $local_cfg) {
        my $local = YAML::XS::LoadFile($local_cfg);
        for my $key (keys %$local) {
            $self->config->{$key} = $local->{$key};
        }
    }

    $self->secrets($self->config->{secrets});
    $self->sessions->cookie_name('mm_session');
    $self->sessions->default_expiration(86400);

    if (!-e $self->dataDir) {
        mkdir $self->dataDir or die("Cannot make dataDir[$!]: " . $self->dataDir);
    }

    if (!$self->ensureActiveSeason) {
        $self->log->warn("No active season. Game controller will auto-create one on first visit.");
    };

    $self->renderer->cache->max_keys(0);
    $self->defaults(layout => 'default');

    $self->helper(is_maintenance => sub ($c) {
        return $c->app->maintenance->in_maintenance;
    });

    $self->helper(skills_data => sub ($c) {
        state $data = YAML::XS::LoadFile($c->app->home . '/content/skills.yml');
        return $data->{skills};
    });

    $self->helper(csrf_token => sub ($c) {
        my $token = $c->session('csrf_token');
        if (!$token) {
            my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
            $token = join '', map { $chars[rand @chars] } 1..32;
            $c->session(csrf_token => $token);
        }
        return $token;
    });

    $self->helper(factions_data => sub ($c) {
        state $data = YAML::XS::LoadFile($c->app->home . '/content/factions.yml');
        return $data->{factions};
    });

    $self->helper(references_data => sub ($c) {
        state $data = YAML::XS::LoadFile($c->app->home . '/content/references.yml');
        return $data->{entries} // [];
    });

    $self->helper(advisories => sub ($c) {
        state $data = YAML::XS::LoadFile($c->app->home . '/content/flavor/advisories.yml');
        return $data->{advisories};
    });

    $self->helper(negotiation_reactions => sub ($c) {
        state $data = YAML::XS::LoadFile($c->app->home . '/content/flavor/negotiation_reactions.yml');
        return $data->{negotiation_reactions};
    });

    $self->helper(customer_portraits => sub ($c) {
        my $dir = $c->app->home . '/public/images/portraits';
        opendir my $dh, $dir or return [];
        my %seen;
        while (my $f = readdir $dh) {
            $seen{$1} = 1 if $f =~ /^(.+?)_happy\.svg$/;
        }
        closedir $dh;
        return [ sort keys %seen ];
    });

    # Fragment format for resource endpoints (Phase 1)
    $self->types->type(fragment => 'text/html');

    $self->helper(current_player => sub ($c) {
        my $player_id = $c->session('playerId');
        return unless $player_id;
        $c->app->session_store->load;
        my $session = $c->app->session_store->find_by_player_id($player_id);
        return unless $session;
        my $timeout = $c->app->config->{session_timeout_minutes} // 60;
        if ($session->is_expired($timeout)) {
            $c->app->session_store->delete($session->getCol('id'));
            $c->session(expires => 1);
            return;
        }
        $session->touch;
        return $player_id;
    });

    $self->_catch_up_maintenance;

    if ($self->mode ne 'test') {
        Mojo::IOLoop->recurring(60 => sub {
            $self->maintenance->dailyMaintenance;
        });

        my $cleanup_interval = $self->config->{rate_limit_cleanup_interval};
        Mojo::IOLoop->recurring($cleanup_interval => sub {
            $self->rate_limiter->cleanup;
        }) if $cleanup_interval;
    }

    $self->buildRoutes;
}

sub _catch_up_maintenance ($self) {
    my $season = $self->active_season;
    return unless $season;

    my $last = $season->getCol('last_maintenance');
    return unless defined $last;

    my $maint = $self->maintenance;
    my $boundary = $maint->recent_maintenance_boundary;

    if ($last < $boundary) {
        my $missed = int(($boundary - $last) / 86400) + 1;
        $self->log->info("Catch-up: $missed missed maintenance cycle(s)");
        $maint->catch_up($missed);
    }
}

sub buildRoutes ($self) {
    my $r = $self->routes;

    # Readiness probe (no auth, no maintenance block, no DB)
    $r->get('/health')->to(cb => sub ($c) { $c->render(json => { ok => 1 }) })->name('health');

    # Public read-only routes (accessible during maintenance)
    $r->get('/')->to('root#index')->name('root');
    $r->get('/login')->to('sessions#login_form')->name('login_form');
    $r->get('/logout')->to('sessions#logout')->name('logout');
    $r->delete('/sessions')->to('sessions#destroy')->name('logout_api');

    # Routes blocked during maintenance
    my $no_maintenance = $r->under('/' => sub ($c) {
        if ($c->is_maintenance) {
            $c->render(text => 'Maintenance in progress', status => 503);
            return;
        }
        return 1;
    });
    my $rate_limited = $no_maintenance->under('/' => sub ($c) {
        my $ip = $c->tx->remote_address;
        $ip = ($c->req->headers->header('X-Forwarded-For') // '') =~ /([^,\s]+)/
            ? $1 : $ip
            if $c->app->config->{rate_limit_trusted_proxies};

        my $rl = $c->app->rate_limiter;

        if (!$rl->check($ip)) {
            my $retry_after = $rl->get_reset_time($ip);
            $c->res->headers->header('Retry-After' => $retry_after);
            $c->render(json => {
                ok => 0, error => 'Too many attempts',
                retry_after => $retry_after,
            }, status => 429);
            return;
        }

        $c->res->headers->header('X-RateLimit-Limit'     => $rl->max_attempts);
        $c->res->headers->header('X-RateLimit-Remaining'  => $rl->get_remaining($ip));
        $c->res->headers->header('X-RateLimit-Reset'      => $rl->get_reset_time($ip));

        return 1;
    });
    $rate_limited->post('/sessions')->to('sessions#create')->name('login');
    $rate_limited->post('/sessions/recover')->to('sessions#recover')->name('recover');
    $no_maintenance->get('/sessions/token-prompt')->to('sessions#token_prompt')->name('token_prompt');
    $no_maintenance->get('/sessions/recovery-form')->to('sessions#recovery_form')->name('recovery_form');
    $no_maintenance->get('/sessions/credentials')->to('sessions#credentials')->name('new_credentials');

    # Admin bridge — X-Admin-Secret header auth, no session/CSRF required
    my $admin_bridge = $no_maintenance->under('/admin' => sub ($c) {
        my $secret = $c->req->headers->header('X-Admin-Secret') // '';
        if ($c->app->auth_service->admin_authenticate($secret)) {
            return 1;
        }
        $c->app->audit_log->log('admin_auth_failed');
        $c->render(json => { ok => 0, error => 'Unauthorized' }, status => 401);
        return;
    });
    $admin_bridge->post('/admin/account/reset-token')->to('admin#reset_token');
    $admin_bridge->post('/admin/account/ban')->to('admin#ban');
    $admin_bridge->post('/admin/account/unban')->to('admin#unban');

    # Game page — outside auth bridge so unauthenticated users see login form in device frame
    $no_maintenance->get('/game')->to('game#show')->name('game');

    # Authenticated routes (also blocked during maintenance)
    my $auth = $no_maintenance->under('/' => sub ($c) {
        my $player_id = $c->current_player;
        if (!$player_id) {
            if (($c->req->headers->accept // '') =~ /json/) {
                $c->render(json => { ok => 0, error => 'Not logged in' }, status => 401);
            } else {
                $c->redirect_to('login_form');
            }
            return;
        }
        return 1;
    });

    # CSRF check for write methods on authenticated routes
    my $auth_write = $auth->under('/' => sub ($c) {
        return 1 if $c->req->method eq 'GET';
        my $header = $c->req->headers->header('X-CSRF-Token') // '';
        my $token  = $c->session('csrf_token') // '';
        if (!($header && $token && $header eq $token)) {
            $c->redirect_to('login_form');
            return;
        }
        return 1;
    });

    # Resource endpoints (fragment/JSON via show action)
    $auth->get('/player')->to('player#show')->name('player');
    $auth->get('/season/recap')->to('season#recap');
    $auth->get('/crier')->to('crier#show');
    $auth->get('/home')->to('home#show');
    $auth->get('/idle')->to('idle#show');
    $auth->get('/prospecting')->to('prospecting#show');
    $auth->get('/market')->to('market#show');
    $auth->get('/shed')->to('shed#index');
    $auth->get('/skills')->to('skills#index');
    $auth->get('/factions')->to('factions#show');
    $auth->get('/reference/:id')->to('reference#show');
    $auth->get('/account')->to('account#show');
    $auth->get('/leaderboard')->to('leaderboard#index');
    $auth->get('/leaderboard/factions')->to('leaderboard#factions');
    $auth->get('/result')->to('result#show')->name('result_show');
    $auth->get('/nav')->to('nav#show');
    $auth->post('/nav/toggle')->to('nav#toggle')->name('nav_toggle');

    # PvP / Rival Pressure
    $auth->get('/pvp')->to('pvp#show')->name('pvp_show');

    # Orientation
    $auth->get('/orientation')->to('orientation#show');
    $auth_write->post('/orientation/dismiss')->to('orientation#dismiss');

    # Onboarding notices
    $auth->get('/onboarding/notice')->to('onboarding_notice#show');
    $auth_write->post('/onboarding/dismiss-notice')->to('onboarding_notice#dismiss');

    # Write routes under CSRF check
    # DEAD-SUPPRESS: endpoint kept for future re-enable; UI button removed per user request
    $auth_write->delete('/player')->to('player#destroy')->name('delete_player');
    $auth_write->post('/skills/purchase')->to('skills#purchase');
    $auth_write->post('/pvp/apply')->to('pvp#apply')->name('pvp_apply');
    $auth_write->post('/prospecting/begin')->to('prospecting#begin');
    $auth_write->post('/prospecting/push')->to('prospecting#push');
    $auth_write->post('/prospecting/stop')->to('prospecting#stop');
    $auth_write->post('/prospecting/resolve_event')->to('prospecting#resolve_event');
    $auth_write->post('/market/begin')->to('market#begin');
    $auth_write->post('/market/offer')->to('market#offer');
    $auth_write->post('/market/send_away')->to('market#send_away');
    $auth_write->post('/market/accept_counter')->to('market#accept_counter');
    $auth_write->post('/market/stand_pat')->to('market#stand_pat');
    $auth_write->post('/result/dismiss')->to('result#dismiss')->name('result_dismiss');
    $auth_write->post('/result/continue')->to('result#do_continue')->name('result_continue');
    # DEAD-SUPPRESS: future season history UI
    # $auth_write->post('/season/end')->to('season#end');
}

sub active_season ($self) {
    $self->seasons->load;
    my $active = $self->seasons->find(sub { ($_[0]->{status} // '') eq 'active' });
    return @$active ? $active->[0] : undef;
}

sub ensureActiveSeason ($self) {
    $self->seasons->load;

    if (!scalar keys %{ $self->seasons->all }) {
        $self->log->info("No season data found. Creating default active season.");
        my $season = $self->seasons->create(
            label           => $self->config->{default_season_label_prefix} . ' 1',
            length          => $self->config->{default_season_length},
            day             => 1,
            end_of_day_hour => $self->config->{end_of_day_hour},
            status          => 'active',
            last_maintenance => CORE::time,
        );
        $season->save;
        return 1;
    }

    my $active = $self->seasons->find(sub { ($_[0]->{status} // '') eq 'active' });
    if (!@$active) {
        $self->log->warn("No active season found. Run 'create-season' to start one.");
        return;
    }
    return 1;
}

=head1 CONFIGURATION

All configuration is optional — every key has a sensible default defined in
C<defaultConfig>. Override any key by creating a F<magic_mountain.yml> in the
application root directory. Set C<$ENV{MM_CFG_FILE}> to use a different path.

=head2 Server & Sessions

=over

=item C<secrets>

Arrayref of strings used by Mojolicious for signed cookies. Default:
C<['override-me']>. B<Must be changed before production.>

=item C<session_timeout_minutes>

Minutes of inactivity before a session expires. Default: C<60>.

=back

=head2 Game Rules

=over

=item C<end_of_day_hour>

Hour (0–23) at which daily maintenance runs. Default: C<0> (midnight).

=item C<default_season_length>

Days per season when auto-created. Default: C<30>.

=item C<default_season_label_prefix>

Label prefix for auto-created seasons. Default: C<Season> (produces
"Season 1", "Season 2", etc.).

=item C<default_daily_turns>

Number of action points restored each day. Default: C<10>. This is stored
per-season at creation time; changing it mid-season has no effect on
existing seasons.

=item C<default_action_points>

Maximum action points a character can hold. Default: C<15>.

=back

=head2 Rate Limiting

=over

=item C<rate_limit_max_attempts>

Failed login attempts from a single IP before a block is triggered.
Default: C<5>.

=item C<rate_limit_max_attempts_per_name>

Failed login attempts for a single account name (from any IP) before a
block is triggered. Names are case-insensitive. Default: C<5>.

=item C<rate_limit_window_minutes>

Sliding window in minutes for counting failed attempts. If an IP or name
makes no attempts within this window, the counter resets. Default: C<15>.

=item C<rate_limit_block_minutes>

Duration in minutes an IP or name is blocked after exceeding the attempt
limit. Default: C<15>.

=item C<rate_limit_cleanup_interval>

Seconds between sweeps that remove stale rate-limit entries from memory.
Default: C<300> (5 minutes).

=item C<rate_limit_trusted_proxies>

If set to a truthy value, the rate limiter reads the original client IP
from the C<X-Forwarded-For> header instead of the direct connection
address. B<Only enable behind a trusted reverse proxy.> Default: C<0>.

=back

=head2 Planned (reserved, not yet read at runtime)

=over

=item C<maintenance_window_minutes>

Reserved for future maintenance route-guard feature. Default: C<5>.

=back

=cut


1;
