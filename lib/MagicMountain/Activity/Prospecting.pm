package MagicMountain::Activity::Prospecting;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

# ── Transition table ────────────────────────────────────────────────

has transitions => sub {
    {
        idle           => ['begin'],
        processing     => ['push', 'stop'],
    }
};

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

sub _draw_artifact ($self, $char) {
    my $specs = $self->_specs;
    die "no artifact specs loaded" unless @$specs;
    my $prosp = $char->getCol('skill_prospecting') // 0;
    my $total_weight = 0;
    for my $spec (@$specs) {
        my $w = $spec->{weight} // 1;
        $w *= 2 if $prosp >= 2 && ($spec->{base_value} // 0) >= 8;
        $total_weight += $w;
    }
    my $roll = rand($total_weight);
    my $cumulative = 0;
    for my $spec (@$specs) {
        my $w = $spec->{weight} // 1;
        $w *= 2 if $prosp >= 2 && ($spec->{base_value} // 0) >= 8;
        $cumulative += $w;
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
    $artifact->{push_count}                   = 0;
    $artifact->{has_evolved}                  = 0;
    $artifact->{value}                        = ($artifact->{base_value} // 5) + ($prosp >= 1 ? 2 : 0) + ($prosp >= 2 ? 2 : 0);
    $artifact->{max_instability}            //= 14;
    $artifact->{instability_growth_min}     //= 1;
    $artifact->{instability_growth_max}     //= 2;
    $artifact->{base_gain_min}              //= 3;
    $artifact->{base_gain_max}              //= 5;
    if ($prosp >= 3) {
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
    die "AP exhausted" unless ($char->getCol('action_points') // 0) >= 2;

    my $spec     = $self->_draw_artifact($char);
    my $artifact = { %$spec };
    $self->_apply_defaults($artifact, $char);
    $artifact->{signal} = $self->_pick_signal($artifact, $artifact->{stage});

    $self->artifact($artifact);
    $self->phase('processing');
    $char->setCol('action_points', $char->getCol('action_points') - 2);
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

# ── push ──────────────────────────────────────────────────────────────

sub push ($self, $char, %params) {
    my $artifact = $self->artifact;
    my $upcyc = $char->getCol('skill_upcycling') // 0;
    my $upcyc_effects = $self->_upcycling_effects($char);

    $artifact->{push_count}++;

    my $growth = $artifact->{instability_growth_min}
               + int(rand($artifact->{instability_growth_max}
                        - $artifact->{instability_growth_min} + 1));
    $growth -= ($upcyc_effects->{instability_growth_reduction} // 0);
    $growth = 1 if $growth < 1;
    $artifact->{instability} += $growth;

    $self->_update_stage($artifact);

    my $ratio           = $artifact->{instability} / $artifact->{max_instability};
    my $collapse_chance = ($ratio ** 3) * 0.80;
    $collapse_chance    = 1.0  if $collapse_chance > 1.0;


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
            ok        => 1,
            result    => 'stopped',
            shed_item => {
                id                   => $item->getCol('id'),
                artifact_id          => $artifact->{id},
                estimated_value_min  => $est_min,
                estimated_value_max  => $est_max,
                condition            => 'fresh',
            },
            player => $self->_player_snapshot($char),
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
