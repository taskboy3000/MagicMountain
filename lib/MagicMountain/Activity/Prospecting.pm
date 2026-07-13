package MagicMountain::Activity::Prospecting;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

# ── Transition table ────────────────────────────────────────────────

has transitions => sub {
    {
        idle           => ['begin'],
        processing     => ['push', 'stop', 'resolve_event'],
    }
};

has _activity_type => sub { 'prospecting' };

# ── Construction ──────────────────────────────────────────────────

sub create ($self, %params) {
    $params{type}  //= 'prospecting';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}

# ── Spec lookup ─────────────────────────────────────────────────────

sub _specs ($self) {
    return $self->content_data // [];
}

sub _find_spec ($self, $artifact_id) {
    for my $spec (@{ $self->_specs }) {
        return $spec if $spec->{id} eq $artifact_id;
    }
    return;
}

# ── Artifact drawing ─────────────────────────────────────────────────

sub _get_spec_weight ($self, $spec, $char) {
    my $weight = $spec->{weight} // 1;
    my $prosp  = $char->getCol('skill_prospecting') // 0;
    $weight *= 2 if $prosp >= 3 && ($spec->{base_value} // 0) >= 8;

    if ($self->app->can('dominance_service') && (my $season = $self->app->active_season)) {
        my $biases = $self->app->dominance_service->draw_biases($season);
        for my $b (@{ $spec->{behaviors} // [] }) {
            $weight *= ($biases->{$b} // 1);
        }
    }

    return int($weight + 0.5);
}

sub _draw_artifact ($self, $char) {
    my $specs = $self->_specs;
    die "no artifact specs loaded" unless @$specs;
    my $total_weight = 0;
    for my $spec (@$specs) {
        $total_weight += $self->_get_spec_weight($spec, $char);
    }
    my $roll = rand($total_weight);
    my $cumulative = 0;
    for my $spec (@$specs) {
        $cumulative += $self->_get_spec_weight($spec, $char);
        if ($roll < $cumulative) {
            return $spec;
        }
    }
    return $specs->[0];
}

# ── Signal text helpers ──────────────────────────────────────────────

sub _pick_signal ($self, $artifact, $stage) {
    my $spec    = $self->_find_spec($artifact->{id});
    my $signals;
    $signals = $spec->{signals}{$stage} if $spec;
    return '' unless $signals && @$signals;
    return $signals->[ int(rand(scalar @$signals)) ];
}

sub _pick_collapse ($self, $artifact) {
    my $spec  = $self->_find_spec($artifact->{id});
    my $texts;
    $texts = $spec->{collapse} if $spec;
    return 'The artifact collapses.' unless $texts && @$texts;
    return $texts->[ int(rand(scalar @$texts)) ];
}

# ── Defaults for artifact spec fields ────────────────────────────────

sub _decay_modifiers ($self, $artifact) {
    my $mods = $artifact->{decay_modifiers} // {};
    my $defaults = {
        fresh_multiplier    => 1.0,
        settling_multiplier => 0.75,
        fading_multiplier   => 0.40,
        settling_day        => 2,
        fading_day          => 5,
    };
    for my $key (keys %$defaults) {
        $mods->{$key} //= $defaults->{$key};
    }
    die "invariant: fading_day ($mods->{fading_day}) must exceed settling_day ($mods->{settling_day})"
        unless $mods->{fading_day} > $mods->{settling_day};
    return $mods;
}

sub _apply_defaults ($self, $artifact, $char) {
    my $prosp = $char->getCol('skill_prospecting') // 0;
    my $upcyc = $char->getCol('skill_upcycling')  // 0;
    my $upcyc_effects = $self->_upcycling_effects($char);

    my $rand_instability = int(rand(8));
    $rand_instability -= $upcyc if ($upcyc_effects->{initial_instability_reduction} // 0);
    $rand_instability = 0 if $rand_instability < 0;
    $artifact->{instability} = ($artifact->{starting_instability} // 0) + $rand_instability;

    if ($self->app->can('dominance_service') && (my $season = $self->app->active_season)) {
        my $mod = $self->app->dominance_service->starting_instability_mod($season);
        $artifact->{instability} += $mod if $mod;
    }

    $artifact->{push_count}                   = 0;
    $artifact->{has_evolved}                  = 0;
    $artifact->{value}                        = ($artifact->{base_value} // 5) + ($prosp >= 2 ? 2 : 0) + ($prosp >= 3 ? 2 : 0);
    $artifact->{max_instability}            //= 14;
    $artifact->{instability_growth_min}     //= 1;
    $artifact->{instability_growth_max}     //= 2;
    $artifact->{base_gain_min}              //= 3;
    $artifact->{base_gain_max}              //= 5;
    if ($prosp >= 4) {
        $artifact->{base_gain_min} += 1;
        $artifact->{base_gain_max} += 1;
    }
    $artifact->{evolution_threshold}        //= 0.25;
    $artifact->{evolution_chance}           //= 0.03;
    $artifact->{evolution_instability_spike} //= 3;
    $artifact->{breakthrough_multiplier_min} //= 1.5;
    $artifact->{breakthrough_multiplier_max} //= 2.5;
    $artifact->{state_thresholds}           //= { stable => 0.30, strained => 0.65 };
    $self->_update_stage($artifact);
    $artifact->{signal}                      = '';
    $artifact->{intro}                       = $artifact->{intro} // '';
    $artifact->{decay_modifiers}             = $self->_decay_modifiers($artifact);
}

# ── Upcycling effects lookup ─────────────────────────────────────────

sub _upcycling_effects ($self, $char) {
    my $upcyc = $char->getCol('skill_upcycling') // 0;
    return {} unless $upcyc > 0;
    my $skills = $self->app->skills_data;
    my ($skill) = grep { $_->{id} eq 'upcycling' } @$skills;
    return {} unless $skill && $skill->{levels} && $skill->{levels}[$upcyc - 1];
    return $skill->{levels}[$upcyc - 1]{effects} // {};
}

# ── Stage determination ──────────────────────────────────────────────

sub _update_stage ($self, $artifact) {
    my $ratio = $artifact->{instability} / $artifact->{max_instability};
    my $t     = $artifact->{state_thresholds};
    if ($ratio <= $t->{stable}) {
        $artifact->{stage} = 'stable';
    } elsif ($ratio <= $t->{strained}) {
        $artifact->{stage} = 'strained';
    } else {
        $artifact->{stage} = 'unstable';
    }
}

# ── Player snapshot helper ───────────────────────────────────────────

sub _player_snapshot ($self, $char) {
    return {
        action_points => $char->getCol('action_points'),
        scrap         => $char->getCol('scrap'),
        score         => $char->getCol('score'),
    };
}

sub _artifact_view ($self, $artifact) {
    return {
        id     => $artifact->{id},
        stage  => $artifact->{stage},
        value  => $artifact->{value},
        signal => $artifact->{signal},
    };
}

# ═══════════════════════════════════════════════════════════════════════
# HANDLERS
# ═══════════════════════════════════════════════════════════════════════

# ── begin ─────────────────────────────────────────────────────────────

sub begin ($self, $char, %params) {
    my $season = $self->app->can('active_season') ? $self->app->active_season : undef;
    my $ap_cost = $season ? $season->daily_modifier('prospect_ap_cost', 2) : 2;
    die "AP exhausted" unless ($char->getCol('action_points') // 0) >= $ap_cost;

    # Check for random event FIRST — if one fires, it replaces the artifact draw
    if ($self->app->can('random_events')) {
        my $event = $self->app->random_events->draw(
            pool    => 'prospecting',
            trigger => 'begin',
            context => {
                char   => $char,
                season => $season,
            },
        );
        if ($event) {
            my $name = $char->getCol('name') // 'unknown';
            $char->setCol('action_points', $char->getCol('action_points') - $ap_cost);
            $self->save;

            if ($event->{choices}) {
                # Choice event: store pending_event, player resolves later
                $self->setCol('pending_event', {
                    pool     => 'prospecting',
                    event_id => $event->{id},
                    text     => $event->{text},
                    day      => $season ? $season->getCol('day') : undef,
                    choices  => $event->{choices},
                });
                $self->phase('processing');
                $self->save;
                $char->setCol('pending_activity_id', $self->getCol('id'));
                $char->save;
                $self->app->log->info(
                    sprintf("Choice event [%s] %s — %s", $event->{id}, $name, $event->{text})
                );
                $self->_log_event($char, {
                    type        => 'random_event',
                    event_id    => $event->{id},
                    has_choices => 1,
                    narrative   => sprintf("%s encountered choice event %s: %s", $name, $event->{id}, $event->{text}),
                });
                return {
                    view => {
                        ok     => 1,
                        result => 'event',
                        event  => {
                            id      => $event->{id},
                            text    => $event->{text},
                            choices => $event->{choices},
                        },
                        player => $self->_player_snapshot($char),
                    },
                };
            }

            # Passive event: effects already applied in draw(); build description
            $char->save;
            my $detail;
            if ($event->{result}) {
                $detail = $event->{result};
            } elsif (my $resolved = $event->{_resolved_effects}) {
                $detail = $self->app->random_events->describe_effects($resolved, 'prospecting');
            }
            chomp $detail if $detail;
            $self->app->log->info(
                sprintf("Random event [%s] %s — %s", $event->{id}, $name, $event->{text})
            );
            $self->_log_event($char, {
                type        => 'random_event',
                event_id    => $event->{id},
                narrative   => sprintf("%s encountered %s: %s", $name, $event->{id}, $event->{text}),
            });
            $self->delete;
            $char->setCol('pending_activity_id', undef);
            $char->setCol('result', {
                outcome      => 'event_passive',
                icon         => 'NOTICE',
                outcome_text => 'Event',
                message      => $event->{text},
                detail       => $detail,
                activity_type => 'prospecting',
            });
            $char->setCol('current_view', 'result');
            $char->save;
            return {
                view => {
                    ok      => 1,
                    result  => 'event_passive',
                    event   => { id => $event->{id}, text => $event->{text} },
                    player  => $self->_player_snapshot($char),
                },
            };
        }
    }

    # No event — normal artifact draw
    my $spec     = $self->_draw_artifact($char);
    my $artifact = { %$spec };
    $self->_apply_defaults($artifact, $char);

    if ($season) {
        my $value_mult = $season->daily_modifier('artifact_value_mult', 1);
        $artifact->{value} = int($artifact->{value} * $value_mult) if $value_mult != 1;
    }

    $artifact->{signal} = $self->_pick_signal($artifact, $artifact->{stage});

    $self->artifact($artifact);
    $self->phase('processing');
    $char->setCol('action_points', $char->getCol('action_points') - $ap_cost);
    $self->save;
    $char->setCol('pending_activity_id', $self->getCol('id'));
    $char->save;

    $self->_log_event($char, {
        type        => 'artifact_start',
        artifact_id => $artifact->{id},
        value       => $artifact->{value},
        instability => $artifact->{instability},
        narrative   => sprintf("%s draws a %s (value %d, instability %d).",
            $char->getCol('name') // 'unknown',
            $artifact->{id}, $artifact->{value}, $artifact->{instability}),
    });

    return {
        view => {
            ok       => 1,
            result   => 'start',
            artifact => {
                id     => $artifact->{id},
                stage  => $artifact->{stage},
                value  => $artifact->{value},
                signal => $artifact->{signal},
                intro  => $artifact->{intro},
            },
            player => $self->_player_snapshot($char),
        },
    };
}

# ── resolve_event ─────────────────────────────────────────────────────

sub resolve_event ($self, $char, %params) {
    my $choice_id = $params{choice_id} or die "choice_id required";

    my $pending = $self->getCol('pending_event')
        or die "no pending event";

    my $season   = $self->app->can('active_season') ? $self->app->active_season : undef;
    my $current_day = $season ? $season->getCol('day') : undef;
    if (defined $current_day && defined $pending->{day}) {
        die "pending event expired" if $pending->{day} != $current_day;
    }

    my ($choice) = grep { $_->{id} eq $choice_id } @{ $pending->{choices} }
        or die "unknown choice '$choice_id'";

    my $ctx = {
        char    => $char,
        artifact => $self->artifact // {},
        season  => $season,
    };

    my $resolved = $self->app->random_events->apply_choice(
        pool          => 'prospecting',
        choice_id     => $choice_id,
        pending_event => $pending,
        context       => $ctx,
    );

    my $description;
    if ($choice->{result}) {
        $description = $choice->{result};
    } else {
        $description = $self->app->random_events->describe_effects($resolved, 'prospecting');
    }
    chomp $description if $description;

    $self->setCol('pending_event', undef);
    $self->save;
    $char->save;

    $self->_log_event($char, {
        type       => 'event_choice',
        event_id   => $pending->{event_id},
        choice_id  => $choice_id,
        narrative  => sprintf("%s chose '%s' for event '%s'.",
            $char->getCol('name') // 'unknown', $choice_id, $pending->{event_id}),
    });

    # Event replaces the prospecting action — end the activity
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->setCol('result', {
        outcome      => 'event_choice',
        icon         => 'EVENT',
        outcome_text => 'Event Complete',
        message      => sprintf("You chose '%s'.", $choice_id),
        detail       => $description,
        activity_type => 'prospecting',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    return {
        view => {
            ok      => 1,
            result  => 'event_choice',
            event   => {
                id        => $pending->{event_id},
                choice_id => $choice_id,
            },
            player  => $self->_player_snapshot($char),
        },
    };
}

# ── push ──────────────────────────────────────────────────────────────

sub push ($self, $char, %params) {
    my $artifact = $self->artifact;
    die "push: no artifact present" unless $artifact && $artifact->{max_instability};
    my $upcyc = $char->getCol('skill_upcycling') // 0;
    my $upcyc_effects = $self->_upcycling_effects($char);

    my $season = $self->app->can('active_season') ? $self->app->active_season : undef;
    $artifact->{push_count}++;

    my $growth = $artifact->{instability_growth_min}
               + int(rand($artifact->{instability_growth_max}
                        - $artifact->{instability_growth_min} + 1));
    $growth -= ($upcyc_effects->{instability_growth_reduction} // 0);
    $growth += $season->daily_modifier('instability_growth_delta', 0) if $season;
    $growth = 1 if $growth < 1;
    $artifact->{instability} += $growth;

    $self->_update_stage($artifact);

    my $ratio           = $artifact->{instability} / $artifact->{max_instability};
    my $collapse_mult   = 1;
    $collapse_mult = $season->daily_modifier('collapse_chance_mult', 1) if $season;
    my $collapse_chance = 0;
    if ($ratio > $artifact->{state_thresholds}{stable}) {
        my $stressed = ($ratio - $artifact->{state_thresholds}{stable}) / (1 - $artifact->{state_thresholds}{stable});
        $collapse_chance = ($stressed ** 3) * 0.80 * $collapse_mult;
    }
    $collapse_chance = 1.0  if $collapse_chance > 1.0;


    if (rand() < $collapse_chance) {
        return $self->_do_collapse($char, $artifact);
    }

    if (   $artifact->{can_evolve}
        && !$artifact->{has_evolved}
        &&  $ratio >= $artifact->{evolution_threshold})
    {
        my $evo_chance = $artifact->{evolution_chance};
        $evo_chance += ($upcyc_effects->{evolution_chance_bonus} // 0);
        if (rand() < $evo_chance) {
            return $self->_do_breakthrough($char, $artifact);
        }
    }

    my $gain = $artifact->{base_gain_min}
             + int(rand($artifact->{base_gain_max}
                      - $artifact->{base_gain_min} + 1));
    $gain += ($upcyc_effects->{value_gain_bonus} // 0);
    $artifact->{value} += $gain;

    $artifact->{signal} = $self->_pick_signal($artifact, $artifact->{stage});

    $self->artifact($artifact);
    $self->save;
    $char->save;

    $self->_log_event($char, {
        type        => 'push',
        artifact_id => $artifact->{id},
        instability => $artifact->{instability},
        ratio       => $ratio,
        stage       => $artifact->{stage},
        narrative   => sprintf("%s pushes the %s. Stage: %s (ratio %.2f, instability %d).",
            $char->getCol('name') // 'unknown',
            $artifact->{id}, $artifact->{stage}, $ratio, $artifact->{instability}),
    });

    return {
        view => {
            ok       => 1,
            result   => 'push',
            artifact => $self->_artifact_view($artifact),
            player   => $self->_player_snapshot($char),
        },
    };
}

# ── stop ───────────────────────────────────────────────────────────────

sub stop ($self, $char, %params) {
    my $artifact = $self->artifact;

    my $sell = $char->getCol('skill_selling') // 0;
    my $range = $sell >= 1 ? 0.15 : 0.20;
    my $est_min = int($artifact->{value} * (1 - $range));
    my $est_max = int($artifact->{value} * (1 + $range));

    my $item = $self->app->shed->create(
        char_id             => $char->getCol('id'),
        artifact_id         => $artifact->{id},
        original_value      => $artifact->{value},
        decayed_value       => $artifact->{value},
        condition           => 'fresh',
        days_in_shed        => 0,
        instability         => $artifact->{instability},
        stage               => $artifact->{stage},
        push_count          => $artifact->{push_count},
        has_evolved         => $artifact->{has_evolved},
        behaviors           => $artifact->{behaviors},
        archetypes          => $artifact->{archetypes},
        estimated_value_min => $est_min,
        estimated_value_max => $est_max,
        decay_modifiers     => $artifact->{decay_modifiers},
    );
    $item->save;

    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    $char->setCol('result', {
        outcome      => 'stopped',
        icon         => 'HALT',
        outcome_text => 'Extraction Complete',
        value        => $artifact->{value},
        message      => 'Artifact modification stopped at optimum stability levels.',
        item_name    => $artifact->{id},
    });
    $char->setCol('current_view', 'result');
    $char->save;

    $self->_log_event($char, {
        type        => 'stop',
        artifact_id => $artifact->{id},
        value       => $artifact->{value},
        est_min     => $est_min,
        est_max     => $est_max,
        narrative   => sprintf("%s stops. %s valued at %d (est. %d-%d).",
            $char->getCol('name') // 'unknown',
            $artifact->{id}, $artifact->{value}, $est_min, $est_max),
    });
    $self->_log_event($char, {
        type         => 'shed_entry',
        shed_item_id => $item->getCol('id'),
        artifact_id  => $artifact->{id},
        narrative    => sprintf("%s placed in shed (fresh).", $artifact->{id}),
    });

    return {
        view => {
            ok      => 1,
            result  => 'stopped',
            reward  => 0,
            message => 'Artifact modification stopped at optimum stability levels.',
            player  => $self->_player_snapshot($char),
        },
    };
}

# ═══════════════════════════════════════════════════════════════════════
# INTERNAL OUTCOMES
# ═══════════════════════════════════════════════════════════════════════

sub _do_collapse ($self, $char, $artifact) {
    my $message = $self->_pick_collapse($artifact);

    $char->setCol('result', {
        outcome      => 'collapse',
        icon         => 'ALERT',
        outcome_text => 'Artifact Collapsed',
        message      => $message,
        item_name    => $artifact->{id},
    });
    $char->setCol('current_view', 'result');
    $self->phase('idle');
    $self->artifact(undef);
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    $self->_log_event($char, {
        type        => 'collapse',
        artifact_id => $artifact->{id},
        instability => $artifact->{instability},
        ratio       => $artifact->{instability} / $artifact->{max_instability},
        narrative   => sprintf("The %s collapses at instability %d! %s",
            $artifact->{id}, $artifact->{instability}, $message),
    });

    return {
        view => {
            ok      => 1,
            result  => 'collapse',
            message => $message,
            reward  => 0,
            player  => $self->_player_snapshot($char),
        },
    };
}

sub _do_breakthrough ($self, $char, $artifact) {
    $artifact->{has_evolved} = 1;

    my $mult = $artifact->{breakthrough_multiplier_min}
             + rand() * ($artifact->{breakthrough_multiplier_max}
                       - $artifact->{breakthrough_multiplier_min});
    my $new_value = int($artifact->{value} * $mult);

    my $sell = $char->getCol('skill_selling') // 0;

    $artifact->{instability} += $artifact->{evolution_instability_spike};
    $artifact->{value} = $new_value;

    my $range = $sell >= 1 ? 0.15 : 0.20;
    my $est_min = int($new_value * (1 - $range));
    my $est_max = int($new_value * (1 + $range));

    my $item = $self->app->shed->create(
        char_id              => $char->getCol('id'),
        artifact_id          => $artifact->{id},
        original_value       => $new_value,
        decayed_value        => $new_value,
        condition            => 'fresh',
        days_in_shed         => 0,
        instability          => $artifact->{instability},
        stage                => $artifact->{stage},
        push_count           => $artifact->{push_count},
        has_evolved          => 1,
        behaviors            => $artifact->{behaviors},
        archetypes           => $artifact->{archetypes},
        estimated_value_min  => $est_min,
        estimated_value_max  => $est_max,
        decay_modifiers      => $artifact->{decay_modifiers},
    );
    $item->save;

    $char->setCol('result', {
        outcome      => 'breakthrough',
        icon         => 'PREMIUM',
        outcome_text => 'Breakthrough!',
        value        => $new_value,
        message      => 'A sudden breakthrough! The artifact reveals unexpected potential.',
        item_name    => $artifact->{id},
    });
    $char->setCol('current_view', 'result');
    $self->phase('idle');
    $self->artifact(undef);
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    $self->_log_event($char, {
        type        => 'breakthrough',
        artifact_id => $artifact->{id},
        reward      => $new_value,
        narrative   => sprintf("Breakthrough! The %s evolved into a %d scrap artifact!",
            $artifact->{id}, $new_value),
    });
    $self->_log_event($char, {
        type         => 'shed_entry',
        shed_item_id => $item->getCol('id'),
        artifact_id  => $artifact->{id},
        narrative    => sprintf("%s placed in shed (breakthrough).", $artifact->{id}),
    });

    return {
        view => {
            ok        => 1,
            result    => 'breakthrough',
            shed_item => {
                id          => $item->getCol('id'),
                artifact_id => $artifact->{id},
                value       => $new_value,
                condition   => 'fresh',
            },
            message => 'A sudden breakthrough! The artifact reveals unexpected potential.',
            player  => $self->_player_snapshot($char),
        },
    };
}

1;
