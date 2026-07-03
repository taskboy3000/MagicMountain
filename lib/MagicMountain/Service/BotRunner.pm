package MagicMountain::Service::BotRunner;
use Mojo::Base -base, -signatures;

use MagicMountain::Bot::PushPolicy;
use MagicMountain::Bot::SellPolicy;
use MagicMountain::Bot::PressurePolicy;
use YAML::XS qw(LoadFile);

my %PRESSURE_RANK = (
    mood_comfortable   => 0,
    mood_interested    => 1,
    mood_wary          => 2,
    mood_strained      => 3,
    mood_leaving       => 4,
    mood_over_absolute => 5,
);

sub _pressure_at_or_beyond {
    my ($state, $threshold) = @_;
    return 0 unless $state && $threshold;
    return ($PRESSURE_RANK{$state} // 0) >= ($PRESSURE_RANK{$threshold} // 0);
}

has app        => sub { die "app is required" };
has transcript => undef;

my %_profile_cache;

sub _load_profile ($self, $profile_id) {
    my $file = $self->app->home . '/content/bots.yml';
    $_profile_cache{$file} //= do {
        my $profiles = -e $file ? LoadFile($file) : [];
        my %by_id;
        for my $p (@$profiles) {
            $by_id{$p->{id}} = $p if $p->{id};
        }
        \%by_id;
    };
    return $_profile_cache{$file}{$profile_id};
}

sub run_day ($self, $char, $profile = undef) {
    $profile //= $self->_load_profile($char->getCol('bot_profile_id'));
    return { ok => 0, error => 'No bot profile' } unless $profile;

    my $app         = $self->app;
    my $prospecting = $app->prospecting;
    my $market      = $app->market;
    my $shed        = $app->shed;
    my $profile_id  = $profile->{id};
    my $push_pol    = $profile->{push_policy};
    my $sell_pol    = $profile->{sell_policy};
    my $char_name   = $char->getCol('name');
    my $transcript  = $self->transcript;
    my $actions     = 0;

    # Prospecting phase
    while (($char->getCol('action_points') // 0) >= 2) {
        my $phase_done = 0;
        eval {
            my $activity = $prospecting->create(char_id => $char->getCol('id'));
            my $result = $activity->dispatch($char, 'begin');
            unless ($result->{view}{ok}) { $phase_done = 1; return; }

            # Random event replaces the prospecting action entirely
            if ($result->{view}{result} eq 'event') {
                # Choice event: auto-resolve with first eligible choice
                my $choices = $result->{view}{event}{choices};
                if ($choices && @$choices) {
                    my $choice_id = $choices->[0]{id};
                    $app->log->info(sprintf("Bot %s auto-resolving choice event '%s' with '%s'.",
                        $char_name // '?', $result->{view}{event}{id}, $choice_id));
                    $activity->dispatch($char, 'resolve_event', choice_id => $choice_id);
                }
                $phase_done = 1; return;
            }
            if ($result->{view}{result} eq 'event_passive') {
                $app->log->info(sprintf("Bot %s encountered passive event '%s'.",
                    $char_name // '?', $result->{view}{event}{id} // '?'));
                $phase_done = 1; return;
            }

            # Normal artifact prospecting: push/stop loop
            while (1) {
                my $r = $activity->dispatch($char, 'push');
                my $view = $r->{view};
                unless ($view->{ok}) { $phase_done = 1; return; }
                $actions++;

                if ($view->{result} eq 'collapse' || $view->{result} eq 'breakthrough') {
                    last;
                }

                if ($view->{result} eq 'push') {
                    my $art = $activity->artifact;
                    my $should_stop = MagicMountain::Bot::PushPolicy::evaluate($char, $art, $push_pol);
                    if ($should_stop) {
                        $activity->dispatch($char, 'stop');
                        if ($transcript) {
                            $transcript->log_event({
                                type       => 'policy_push_stop',
                                player     => $char_name,
                                profile_id => $profile_id,
                                policy     => $push_pol->{name},
                                params     => $push_pol->{params},
                                stage      => $art->{stage},
                                value      => $art->{value},
                                push_count => $art->{push_count},
                                narrative  => sprintf("%s stopped pushing via %s (stage=%s, value=%d, pushes=%d).",
                                    $char_name, $push_pol->{name},
                                    $art->{stage} // '?',
                                    $art->{value} // 0,
                                    $art->{push_count} // 0),
                            });
                        }
                        last;
                    }
                }
            }
        };
        if ($@) {
            $app->log->warn(sprintf("Bot %s prospecting error: %s", $char_name // '?', $@));
            last;
        }
        last if $phase_done;
    }

    # Market phase
    while (($char->getCol('action_points') // 0) >= 1) {
        my $phase_done = 0;
        eval {
            my $shed_items = $shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
            unless (@$shed_items) { $phase_done = 1; return; }

            if ($sell_pol->{name} eq 'hoarder') {
                if ($transcript) {
                    $transcript->log_event({
                        type       => 'policy_skip_market',
                        player     => $char_name,
                        profile_id => $profile_id,
                        reason     => 'hoarder',
                        narrative  => sprintf("%s skipped market (hoarder policy).", $char_name),
                    });
                }
                $phase_done = 1;
                return;
            }

            my $activity = $market->create(char_id => $char->getCol('id'));
            my $result = $activity->dispatch($char, 'begin');
            unless ($result->{view}{ok}) { $phase_done = 1; return; }
            $actions++;

            # Market event replaces the visit entirely
            if ($result->{view}{result} eq 'event_passive') {
                $app->log->info(sprintf("Bot %s encountered market event '%s'.",
                    $char_name // '?', $result->{view}{event}{id} // '?'));
                $phase_done = 1;
                return;
            }

            if (!MagicMountain::Bot::SellPolicy::accept_customer($char, $activity->customer, $sell_pol)) {
                $activity->dispatch($char, 'send_away');
                if ($transcript) {
                    $transcript->log_event({
                        type       => 'policy_send_away',
                        player     => $char_name,
                        profile_id => $profile_id,
                        reason     => $sell_pol->{name},
                        narrative  => sprintf("%s sent away customer (%s policy).",
                            $char_name, $sell_pol->{name}),
                    });
                }
                $phase_done = 1;
                return;
            }

            my $sell_params        = $sell_pol->{params} // {};
            my $max_irritation     = $sell_params->{max_irritation} // 3;
            my $max_pressure_state = $sell_params->{max_pressure_state} // 'mood_wary';

            my $keep_offering = 1;
            while ($keep_offering) {
                my $current_items = $shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
                last unless @$current_items;

                for my $item (@$current_items) {
                    if (!MagicMountain::Bot::SellPolicy::should_offer_item($char, $item, $sell_pol)) {
                        if ($transcript) {
                            $transcript->log_event({
                                type       => 'policy_skip_item',
                                player     => $char_name,
                                profile_id => $profile_id,
                                reason     => $sell_pol->{name},
                                value      => $item->getCol('decayed_value') // 0,
                                narrative  => sprintf("%s skipped item %s (value=%d, %s policy).",
                                    $char_name, $item->getCol('artifact_id') // '?',
                                    $item->getCol('decayed_value') // 0, $sell_pol->{name}),
                            });
                        }
                        next;
                    }

                    my $r = $activity->dispatch($char, 'offer', shed_item_id => $item->getCol('id'));
                    my $view = $r->{view};
                    $view->{player}{name} = $char_name;
                    $view->{player}{profile_id} = $profile_id;
                    $actions++;

                    if ($view->{result} eq 'sold') {
                        $keep_offering = 0;
                        last;
                    }

                    if ($view->{result} eq 'sold_more') {
                        if (_pressure_at_or_beyond($view->{pressure_state}, $max_pressure_state)) {
                            $activity->dispatch($char, 'send_away');
                            $keep_offering = 0;
                        } elsif ($view->{irritation} >= $max_irritation) {
                            $activity->dispatch($char, 'send_away');
                            $keep_offering = 0;
                        }
                        last;
                    }

                    if ($view->{result} eq 'counter_offer') {
                        my $decayed = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
                        if (MagicMountain::Bot::SellPolicy::should_accept_counter($char, $view->{counter_value}, $decayed, $sell_pol)) {
                            my $r2 = $activity->dispatch($char, 'accept_counter');
                            my $v2 = $r2->{view};
                            $actions++;
                            if ($v2->{result} eq 'sold_more') {
                                if (_pressure_at_or_beyond($v2->{pressure_state}, $max_pressure_state)) {
                                    $activity->dispatch($char, 'send_away');
                                    $keep_offering = 0;
                                } elsif ($v2->{irritation} >= $max_irritation) {
                                    $activity->dispatch($char, 'send_away');
                                    $keep_offering = 0;
                                }
                                last;
                            }
                            $keep_offering = 0;
                            last;
                        }
                        if (!MagicMountain::Bot::SellPolicy::try_another($char, $view, $activity->customer, $sell_pol)) {
                            if ($transcript) {
                                $transcript->log_event({
                                    type       => 'policy_stop_offer',
                                    player     => $char_name,
                                    profile_id => $profile_id,
                                    reason     => $sell_pol->{name},
                                    narrative  => sprintf("%s stopped offering (%s policy).",
                                        $char_name, $sell_pol->{name}),
                                });
                            }
                            $keep_offering = 0;
                            last;
                        }
                        next;
                    }

                    if ($view->{result} eq 'over_budget') {
                        next;
                    }

                    if ($view->{result} eq 'customer_left') {
                        $keep_offering = 0;
                        last;
                    }

                    if ($view->{result} eq 'no_match') {
                        if (!MagicMountain::Bot::SellPolicy::try_another($char, $view, $activity->customer, $sell_pol)) {
                            if ($transcript) {
                                $transcript->log_event({
                                    type       => 'policy_stop_offer',
                                    player     => $char_name,
                                    profile_id => $profile_id,
                                    reason     => $sell_pol->{name},
                                    narrative  => sprintf("%s stopped offering (%s policy).",
                                        $char_name, $sell_pol->{name}),
                                });
                            }
                            $keep_offering = 0;
                            last;
                        }
                        next;
                    }
                }
                $keep_offering = 0;
            }
        };
        if ($@) {
            $app->log->warn(sprintf("Bot %s market error: %s", $char_name // '?', $@));
            last;
        }
        last if $phase_done;
    }

    # Pressure phase (after market so scrap is final available)
    if ($self->app->config->{pvp_enabled}) {
        my $pvp_svc = $self->app->can('pvp_service') ? $self->app->pvp_service : undef;
        if ($pvp_svc) {
            my $policy = MagicMountain::Bot::PressurePolicy->new;
            $app->characters->load;
            my $season = $app->active_season;
            if ($season) {
                my $chars = $app->characters->find(
                    sub { $_[0]->{season_id} eq $season->getCol('id') });
                $app->pressures->load;
                my $pressures_from_bot = $app->pressures->find(
                    sub { $_[0]->{attacker_id} eq $char->getCol('id')
                           && !$_[0]->{attacker_consumed} });

                my %profiles;
                for my $c (@$chars) {
                    $profiles{$c->getCol('id')} = $self->_load_profile($c->getCol('bot_profile_id'))
                        if $c->getCol('bot_profile_id');
                }

                my $decision = $policy->decide($char, {
                    app                => $app,
                    season             => $season,
                    characters         => $chars,
                    profiles           => \%profiles,
                    pressures_from_bot => $pressures_from_bot,
                });

                if ($decision) {
                    my $result = $pvp_svc->apply_pressure(
                        $char, $decision->{target_id},
                        $decision->{faction_id}, $decision->{effect_type});
                    if ($result->{ok} && $transcript) {
                        $transcript->log_event({
                            type    => 'pressure_applied_bot',
                            player  => $char_name,
                            profile => $profile_id,
                            target  => $decision->{target_id},
                            faction => $decision->{faction_id},
                            effect  => $decision->{effect_type},
                        });
                    }
                }
            }
        }
    }

    return { ok => 1, actions => $actions };
}

1;
