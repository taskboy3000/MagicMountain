package MagicMountain::Activity::Prospecting;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

# ── Transition table ────────────────────────────────────────────────

has transitions => sub {
    {
        idle           => ['begin'],
        processing     => ['push', 'stop'],
        awaiting_buyer => ['sell'],
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

sub _draw_artifact ($self) {
    my $specs = $self->_specs;
    die "no artifact specs loaded" unless @$specs;
    my $total_weight = 0;
    $total_weight += $_->{weight} // 1 for @$specs;
    my $roll = rand($total_weight);
    my $cumulative = 0;
    for my $spec (@$specs) {
        $cumulative += $spec->{weight} // 1;
        if ($roll < $cumulative) {
            return $spec;
        }
    }
    return $specs->[0];
}

# ── Signal text helpers ──────────────────────────────────────────────

sub _pick_signal ($self, $artifact, $stage) {
    my $spec    = $self->_find_spec($artifact->{id});
    my $signals = $spec->{signals}{$stage} if $spec;
    return '' unless $signals && @$signals;
    return $signals->[ int(rand(scalar @$signals)) ];
}

sub _pick_collapse ($self, $artifact) {
    my $spec  = $self->_find_spec($artifact->{id});
    my $texts = $spec->{collapse} if $spec;
    return 'The artifact collapses.' unless $texts && @$texts;
    return $texts->[ int(rand(scalar @$texts)) ];
}

# ── Defaults for artifact spec fields ────────────────────────────────

sub _apply_defaults ($self, $artifact) {
    $artifact->{instability}                  = $artifact->{starting_instability} // 0;
    $artifact->{push_count}                   = 0;
    $artifact->{has_evolved}                  = 0;
    $artifact->{value}                        = $artifact->{base_value} // 5;
    $artifact->{max_instability}            //= 12;
    $artifact->{instability_growth_min}     //= 1;
    $artifact->{instability_growth_max}     //= 3;
    $artifact->{base_gain_min}              //= 2;
    $artifact->{base_gain_max}              //= 5;
    $artifact->{evolution_threshold}        //= 0.50;
    $artifact->{evolution_chance}           //= 0.08;
    $artifact->{evolution_instability_spike} //= 3;
    $artifact->{breakthrough_multiplier_min} //= 1.5;
    $artifact->{breakthrough_multiplier_max} //= 2.5;
    $artifact->{state_thresholds}           //= { stable => 0.30, strained => 0.65 };
    $artifact->{stage}                       = 'stable';
    $artifact->{signal}                      = '';
    $artifact->{intro}                       = $artifact->{intro} // '';
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
        turns_remaining => $char->{turns_remaining},
        scrap           => $char->{scrap} // 0,
        score           => $char->{score} // 0,
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
    die "turns exhausted" unless ($char->{turns_remaining} // 0) > 0;

    my $spec     = $self->_draw_artifact;
    my $artifact = { %$spec };
    $self->_apply_defaults($artifact);
    $artifact->{signal} = $self->_pick_signal($artifact, 'stable');

    $self->artifact($artifact);
    $self->phase('processing');
    $char->{turns_remaining}--;

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

    $artifact->{push_count}++;

    my $growth = $artifact->{instability_growth_min}
               + int(rand($artifact->{instability_growth_max}
                        - $artifact->{instability_growth_min} + 1));
    $artifact->{instability} += $growth;

    $self->_update_stage($artifact);

    my $ratio           = $artifact->{instability} / $artifact->{max_instability};
    my $collapse_chance = $ratio * 0.8;
    $collapse_chance    = 1.0  if $collapse_chance > 1.0;
    $collapse_chance    = 0.05 if $collapse_chance < 0.05;

    if (rand() < $collapse_chance) {
        return $self->_do_collapse($char, $artifact);
    }

    if (   $artifact->{can_evolve}
        && !$artifact->{has_evolved}
        &&  $ratio >= $artifact->{evolution_threshold})
    {
        if (rand() < $artifact->{evolution_chance}) {
            return $self->_do_breakthrough($char, $artifact);
        }
    }

    my $gain = $artifact->{base_gain_min}
             + int(rand($artifact->{base_gain_max}
                      - $artifact->{base_gain_min} + 1));
    $artifact->{value} += $gain;

    $artifact->{signal} = $self->_pick_signal($artifact, $artifact->{stage});

    $self->artifact($artifact);

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

    my $offers = [
        {
            faction_id   => 'syndicate',
            faction_name => 'The Syndicate',
            value        => int($artifact->{value} * 1.1),
            text         => 'The Syndicate offers ' . int($artifact->{value} * 1.1) . ' scrap.',
            disposition  => 'pragmatic',
        },
        {
            faction_id   => 'faculty',
            faction_name => 'The Faculty',
            value        => int($artifact->{value} * 0.9),
            text         => 'The Faculty offers ' . int($artifact->{value} * 0.9) . ' scrap.',
            disposition  => 'scholarly',
        },
    ];

    $self->offers($offers);
    $self->phase('awaiting_buyer');

    return {
        view => {
            ok           => 1,
            result       => 'stop',
            pending_sale => { offers => $offers },
            artifact     => $self->_artifact_view($artifact),
            player       => $self->_player_snapshot($char),
        },
    };
}

# ── sell ───────────────────────────────────────────────────────────────

sub sell ($self, $char, %params) {
    my $faction_id = $params{faction_id} or die "faction_id is required";
    my $offers     = $self->offers;

    my ($chosen) = grep { $_->{faction_id} eq $faction_id } @{$offers // []};
    die "invalid faction_id: $faction_id" unless $chosen;

    my $value = $chosen->{value};
    $char->{scrap} += $value;
    $char->{score} += $value;

    $self->phase('idle');
    $self->artifact(undef);
    $self->offers(undef);

    return {
        view => {
            ok            => 1,
            result        => 'sold',
            value_awarded => $value,
            faction_id    => $faction_id,
            player        => $self->_player_snapshot($char),
        },
    };
}

# ═══════════════════════════════════════════════════════════════════════
# INTERNAL OUTCOMES
# ═══════════════════════════════════════════════════════════════════════

sub _do_collapse ($self, $char, $artifact) {
    my $message = $self->_pick_collapse($artifact);

    $self->phase('idle');
    $self->artifact(undef);
    $self->offers(undef);

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

    $artifact->{instability} += $artifact->{evolution_instability_spike};

    $char->{scrap} += $new_value;
    $char->{score} += $new_value;

    $self->phase('idle');
    $self->artifact(undef);
    $self->offers(undef);

    return {
        view => {
            ok      => 1,
            result  => 'breakthrough',
            reward  => $new_value,
            message => 'A sudden breakthrough! The artifact reveals unexpected potential.',
            player  => $self->_player_snapshot($char),
        },
    };
}

1;
