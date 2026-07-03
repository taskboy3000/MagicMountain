package MagicMountain::Service::RandomEvents;
use Modern::Perl;
use Mojo::Base -base, -signatures;
use YAML::XS qw(LoadFile);

has app => undef;

# Per-pool per-trigger probability that any event fires.
# YAML weights control which event; this controls whether.
has event_chance => sub { +{
    prospecting  => { begin => 0.20 },
    market_visit => { begin => 0.15 },
} };

# ── Condition registries (pool-specific) ────────────────────────────

has conditions_by_pool => sub { +{
    prospecting => {
        artifact_stage => {
            label      => 'Artifact stage is',
            value_type => 'string',
            accepts    => ['scalar'],
            values     => ['stable', 'strained', 'unstable'],
            handler    => sub ($ctx, $val) { ($ctx->{artifact}{stage} // '') eq $val },
        },
        scrap_gte => {
            label      => 'Scrap >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 9999],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('scrap') // 0) >= $n },
        },
        scrap_lte => {
            label      => 'Scrap <= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 9999],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('scrap') // 0) <= $n },
        },
        score_lte => {
            label      => 'Score <= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 99999],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('score') // 0) <= $n },
        },
        prospecting_gte => {
            label      => 'Prospecting skill >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 4],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_prospecting') // 0) >= $n },
        },
        upcycling_gte => {
            label      => 'Upcycling skill >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 4],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_upcycling') // 0) >= $n },
        },
        selling_gte => {
            label      => 'Selling skill >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 4],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_selling') // 0) >= $n },
        },
    },
    market_visit => {
        scrap_gte => {
            label      => 'Scrap >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 9999],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('scrap') // 0) >= $n },
        },
        selling_gte => {
            label      => 'Selling skill >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 4],
            handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_selling') // 0) >= $n },
        },
        standing_gte => {
            label      => 'Standing >= N',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 20],
            handler    => sub ($ctx, $n) { ($ctx->{standing}{$ctx->{customer}{faction_id}} // 0) >= $n },
        },
    },
    global => {
        any_faction_days_no_buy_gte => {
            label      => 'Any faction idle for >= N days',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 99],
            handler    => sub ($ctx, $n) {
                my $fs = $ctx->{faction_state} // {};
                for my $fid (keys %$fs) {
                    return 1 if ($fs->{$fid}{days_since_purchase} // 0) >= $n;
                }
                return 0;
            },
        },
    },
}};

has effects_by_pool => sub { +{
    prospecting => {
        scrap_delta => {
            label      => 'Adjust scrap',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-100, 500],
            handler    => sub ($ctx, $n) { $ctx->{char}->add_scrap($n) },
        },
        score_delta => {
            label      => 'Adjust score',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [0, 25],
            pools      => ['prospecting'],
            handler    => sub ($ctx, $n) { $ctx->{char}->add_score($n) },
        },
        value_delta => {
            label      => 'Adjust artifact value',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-10, 50],
            handler    => sub ($ctx, $n) { $ctx->{artifact}{value} += $n },
        },
        instability_delta => {
            label      => 'Adjust artifact instability',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-5, 10],
            handler    => sub ($ctx, $n) { $ctx->{artifact}{instability} += $n },
        },
        behavior_add => {
            label      => 'Add behavior tag',
            value_type => 'string',
            accepts    => ['scalar'],
            handler    => sub ($ctx, $tag) {
                push @{ $ctx->{artifact}{behaviors} }, $tag;
            },
        },
        ap_delta => {
            label      => 'Adjust AP',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-3, 1],
            handler    => sub ($ctx, $n) {
                my $ap  = $ctx->{char}->getCol('action_points') + $n;
                my $max = $ctx->{char}->getCol('action_points_max') // 15;
                $ap = 0  if $ap < 0;
                $ap = $max if $ap > $max;
                $ctx->{char}->setCol('action_points', $ap);
            },
        },
    },
    market_visit => {
        scrap_delta => {
            label      => 'Adjust scrap',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-100, 500],
            handler    => sub ($ctx, $n) { $ctx->{char}->add_scrap($n) },
        },
        score_delta => {
            label      => 'Adjust score',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [0, 25],
            pools      => ['market_visit'],
            handler    => sub ($ctx, $n) { $ctx->{char}->add_score($n) },
        },
        multiplier_delta => {
            label      => 'Adjust offer multiplier',
            value_type => 'float',
            accepts    => ['scalar'],
            bounds     => [-0.50, 0.50],
            handler    => sub ($ctx, $n) {
                $ctx->{customer}{_multiplier_delta} += $n;
            },
        },
        irritation_floor => {
            label      => 'Set minimum irritation',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 10],
            handler    => sub ($ctx, $n) {
                $ctx->{customer}{_irritation_floor} = $n;
            },
        },
        irritation_delta => {
            label      => 'Adjust irritation',
            value_type => 'integer',
            accepts    => ['scalar', 'range'],
            bounds     => [-3, 5],
            handler    => sub ($ctx, $n) {
                $ctx->{customer}{irritation} += $n;
            },
        },
    },
    global => {
        instability_growth_delta => {
            label      => 'Daily instability growth bonus',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [0, 5],
            handler    => sub ($ctx, $n) {
                $ctx->{season}->setCol('daily_modifiers', {
                    %{ $ctx->{season}->getCol('daily_modifiers') // {} },
                    instability_growth_delta => $n,
                });
            },
        },
        artifact_value_mult => {
            label      => 'Artifact value multiplier',
            value_type => 'float',
            accepts    => ['scalar'],
            bounds     => [0.5, 2.0],
            handler    => sub ($ctx, $n) {
                $ctx->{season}->setCol('daily_modifiers', {
                    %{ $ctx->{season}->getCol('daily_modifiers') // {} },
                    artifact_value_mult => $n,
                });
            },
        },
        market_multiplier_delta => {
            label      => 'Market multiplier delta',
            value_type => 'float',
            accepts    => ['scalar'],
            bounds     => [-0.50, 0.50],
            handler    => sub ($ctx, $n) {
                $ctx->{season}->setCol('daily_modifiers', {
                    %{ $ctx->{season}->getCol('daily_modifiers') // {} },
                    market_multiplier_delta => $n,
                });
            },
        },
        prospect_ap_cost => {
            label      => 'Prospecting AP cost',
            value_type => 'integer',
            accepts    => ['scalar'],
            bounds     => [1, 4],
            handler    => sub ($ctx, $n) {
                $ctx->{season}->setCol('daily_modifiers', {
                    %{ $ctx->{season}->getCol('daily_modifiers') // {} },
                    prospect_ap_cost => $n,
                });
            },
        },
    },
}};

# ── Internal state ───────────────────────────────────────────────────

has _loaded_pools => sub { {} };
has _pool_config => sub { {} };

# ── Format templates (data-driven dispatch for effect descriptions) ──

has format_templates => sub { +{
    prospecting => {
        scrap_delta      => sub ($n) { $n >= 0 ? "Gained $n scrap"  : "Lost " . (-$n) . " scrap" },
        score_delta      => sub ($n) { "Score +$n" },
        value_delta      => sub ($n) { $n >= 0 ? "Artifact value +$n" : "Artifact value $n" },
        instability_delta => sub ($n) { $n >= 0 ? "Instability +$n" : "Instability $n" },
        behavior_add     => sub ($n) { "Artifact gains '$n' behavior" },
        ap_delta         => sub ($n) { $n >= 0 ? "Refunded $n AP" : "Cost " . (-$n) . " AP" },
    },
    market_visit => {
        scrap_delta      => sub ($n) { $n >= 0 ? "Gained $n scrap"  : "Lost " . (-$n) . " scrap" },
        score_delta      => sub ($n) { "Score +$n" },
        multiplier_delta => sub ($n) { my $p = $n * 100; $p >= 0 ? "Offer multiplier +${p}%" : "Offer multiplier ${p}%" },
        irritation_floor => sub ($n) { "Minimum customer irritation: $n" },
        irritation_delta => sub ($n) { $n >= 0 ? "Customer irritation +$n" : "Customer irritation $n" },
    },
    global => {
        instability_growth_delta => sub ($n) { "Daily instability growth: +$n" },
        artifact_value_mult      => sub ($n) { "Today's artifact values: x$n" },
        market_multiplier_delta  => sub ($n) { my $p = $n * 100; "Today's market offers: ${p}%" },
        prospect_ap_cost         => sub ($n) { "Prospecting AP cost: $n" },
    },
} };

sub _format_effect ($self, $pool, $name, $value) {
    my $fmt = $self->format_templates->{$pool}{$name}
        or die "no format template for '$name' in pool '$pool'";
    return $fmt->($value);
}

sub describe_effects ($self, $resolved_values, $pool) {
    return '' unless $resolved_values && @$resolved_values;
    return join('. ', map { $self->_format_effect($pool, $_->{name}, $_->{value}) } @$resolved_values) . '.';
}

# ── Public API ───────────────────────────────────────────────────────

sub draw ($self, %args) {
    my $pool    = $args{pool}    or die "pool required";
    my $trigger = $args{trigger} or die "trigger required";
    my $rng     = $args{seeded_rng};

    return undef if $self->app && $self->app->mode eq 'test' && !$ENV{MM_EVENTS};

    # Ensure pool is loaded so _pool_config is populated (YAML may set event_chance)
    $self->_events_for_pool($pool);

    # Pool-level event_chance from YAML overrides hardcoded default
    my $pool_cfg = $self->_pool_config->{$pool} // {};
    my $chance = defined $pool_cfg->{event_chance}
        ? $pool_cfg->{event_chance}{$trigger}
        : $self->event_chance->{$pool}{$trigger};
    $chance // return undef;

    my $roll = $rng ? $rng->() : rand();
    return undef if $roll >= $chance;

    my $ctx = $args{context} // {};

    my $event_def = $self->_select($pool, $trigger, $ctx);
    return undef unless $event_def;

    # Choice events: return with choices populated, effects NOT applied.
    # Caller must call apply_choice() to resolve.
    if ($event_def->{choices}) {
        my @resolved;
        for my $choice (@{ $event_def->{choices} }) {
            push @resolved, {
                id      => $choice->{id},
                label   => $choice->{label},
                effects => $choice->{effects},
                result  => $choice->{result},
                attrs => {
                    'data-action-url' => '/prospecting/resolve_event',
                    'data-method'     => 'POST',
                    'data-choice-id'  => $choice->{id},
                    class             => 'mm-btn mm-btn-primary',
                },
            };
        }
        return {
            id      => $event_def->{id},
            text    => $event_def->{text},
            result  => $event_def->{result},
            choices => \@resolved,
        };
    }

    # Passive events: apply effects inline, return resolved values for description
    my $resolved = $self->apply_effects($event_def, $pool, $ctx, $rng);

    return {
        id               => $event_def->{id},
        text             => $event_def->{text},
        result           => $event_def->{result},
        _resolved_effects => $resolved,
    };
}

sub apply_effects ($self, $event_def, $pool, $ctx, $rng) {
    my @resolved;
    for my $eff (@{ $event_def->{effects} // [] }) {
        my ($name, $raw) = %$eff;
        my $spec = $self->effects_by_pool->{$pool}{$name}
            or die "handler '$name' not registered for pool '$pool'";
        my $val = $self->_resolve_value($raw, $spec, $rng);
        $spec->{handler}->($ctx, $val);
        push @resolved, { name => $name, value => $val };
    }
    return \@resolved;
}

sub apply_choice ($self, %args) {
    my $pool     = $args{pool}     or die "pool required";
    my $choice_id = $args{choice_id} or die "choice_id required";
    my $pending  = $args{pending_event} or die "pending_event required";
    my $ctx      = $args{context}  // {};
    my $rng      = $args{seeded_rng};

    my ($choice) = grep { $_->{id} eq $choice_id } @{ $pending->{choices} }
        or die "unknown choice '$choice_id'";

    return $self->apply_effects($choice, $pool, $ctx, $rng);
}

# ── Selection ────────────────────────────────────────────────────────

sub _select ($self, $pool, $trigger, $ctx) {
    my $events = $self->_events_for_pool($pool);
    return undef unless $events && @$events;

    my $season = $ctx->{season};
    my $day    = $season ? ($season->{day} // $season->getCol('day')) : undef;

    my @candidates;
    for my $event (@$events) {
        next unless ($event->{trigger} // '') eq $trigger;
        next if defined($day) && defined($event->{min_day}) && $day < $event->{min_day};
        next if defined($day) && defined($event->{max_day}) && $day > $event->{max_day};
        next unless $self->_conditions_pass($event, $pool, $ctx);

        # For choice events, filter out choices that fail conditions.
        # Discard event entirely if no choices remain.
        if ($event->{choices}) {
            my @eligible;
            for my $choice (@{ $event->{choices} }) {
                push @eligible, $choice if $self->_conditions_pass($choice, $pool, $ctx);
            }
            next unless @eligible;
            # Store filtered choices on a temp key; draw() reads 'choices'
            $event->{_filtered_choices} = \@eligible;
        }

        push @candidates, $event;
    }

    return undef unless @candidates;

    # Resolve _filtered_choices into 'choices' for the selected event
    for my $c (@candidates) {
        if ($c->{_filtered_choices}) {
            $c->{choices} = $c->{_filtered_choices};
            delete $c->{_filtered_choices};
        }
    }

    my $total_weight = 0;
    $_->{_cumulative} = ($total_weight += ($_->{weight} // 1)) for @candidates;

    my $roll = rand($total_weight);
    for my $c (@candidates) {
        return $c if $roll < $c->{_cumulative};
    }
    return $candidates[0];
}

sub _conditions_pass ($self, $event, $pool, $ctx) {
    return 1 unless $event->{conditions} && @{ $event->{conditions} };
    for my $cond (@{ $event->{conditions} }) {
        my ($name, $val) = %$cond;
        my $spec = $self->conditions_by_pool->{$pool}{$name};
        return 0 unless $spec;
        return 0 unless $spec->{handler}->($ctx, $val);
    }
    return 1;
}

# ── Value resolution ─────────────────────────────────────────────────

sub _resolve_value ($self, $raw, $spec, $rng) {
    return $raw unless ref $raw eq 'ARRAY';
    die "range not allowed for " . ($spec->{label} // 'effect')
        unless grep { $_ eq 'range' } @{ $spec->{accepts} };
    my ($min, $max) = @$raw;
    die "range must have exactly two integer elements"
        unless defined($min) && defined($max) && $min =~ /^-?\d+$/ && $max =~ /^-?\d+$/;
    die "range reversed: $min > $max" if $min > $max;
    my $r = $rng ? $rng->() : rand();
    return $min + int($r * ($max - $min + 1));
}

# ── YAML loading ─────────────────────────────────────────────────────

sub _events_for_pool ($self, $pool) {
    return $self->_loaded_pools->{$pool} if $self->_loaded_pools->{$pool};
    $self->_load($pool);
    return $self->_loaded_pools->{$pool} // [];
}

sub _load ($self, $pool) {
    my $file = $self->app->home . "/content/events/$pool.yml";
    return [] unless -f $file;

    my $yaml = LoadFile($file);

    # Support two formats:
    #   array  — flat list of events (legacy)
    #   hash   — { event_chance: { begin: 1.0 }, events: [...] }
    my $events;
    if (ref $yaml eq 'HASH') {
        if (my $ec = $yaml->{event_chance}) {
            $self->_pool_config->{$pool}{event_chance} = $ec;
        }
        $events = $yaml->{events};
        die "$pool events: 'events' key must be an array" unless ref $events eq 'ARRAY';
    } elsif (ref $yaml eq 'ARRAY') {
        $events = $yaml;
    } else {
        die "$pool events must be an array or hash";
    }

    my %seen_ids;
    for my $event (@$events) {
        my $eid = $event->{id} // 'UNDEFINED';
        die "event '$eid': must have 'id'" unless defined $event->{id};
        die "event '$eid': id must be ^[a-z][a-z0-9_]*\$" unless $event->{id} =~ /^[a-z][a-z0-9_]*$/;
        die "duplicate event id '$eid'" if $seen_ids{$eid}++;

        die "event '$eid': must have 'trigger'" unless defined $event->{trigger};
        die "event '$eid': invalid trigger '$event->{trigger}'"
            unless $event->{trigger} =~ /^(begin|day_start)$/;
        die "event '$eid': must have 'weight'" unless defined $event->{weight};
        die "event '$eid': weight must be positive integer"
            unless $event->{weight} =~ /^\d+$/ && $event->{weight} > 0;
        die "event '$eid': must have 'text'" unless defined $event->{text} && length($event->{text}) > 0;

        die "event '$eid': result must be a non-empty string"
            if defined $event->{result} && (!ref($event->{result}) && length($event->{result}) == 0 || ref $event->{result});

        die "event '$eid': min_day > max_day"
            if defined($event->{min_day}) && defined($event->{max_day}) && $event->{min_day} > $event->{max_day};

        if ($event->{choices}) {
            die "event '$eid': choices must be an array" unless ref $event->{choices} eq 'ARRAY';
            die "event '$eid': choices and effects are mutually exclusive"
                if $event->{effects} && @{ $event->{effects} };
            die "event '$eid': must have at least one choice" unless @{ $event->{choices} };
            my %seen_cids;
            for my $choice (@{ $event->{choices} }) {
                my $cid = $choice->{id} // 'UNDEFINED';
                die "choice '$cid' in event '$eid': must have 'id'" unless defined $choice->{id};
                die "choice '$cid' in event '$eid': duplicate id" if $seen_cids{$cid}++;
                die "choice '$cid' in event '$eid': must have 'label'" unless defined $choice->{label};
                die "choice '$cid' in event '$eid': must have 'effects'"
                    unless $choice->{effects} && @{ $choice->{effects} };
                die "choice '$cid' in event '$eid': result must be a non-empty string"
                    if defined $choice->{result} && (!ref($choice->{result}) && length($choice->{result}) == 0 || ref $choice->{result});
                for my $eff (@{ $choice->{effects} }) {
                    my ($name) = %$eff;
                    my $spec = $self->effects_by_pool->{$pool}{$name}
                        or die "choice '$cid' in event '$eid': unknown effect '$name'";
                }
                for my $cond (@{ $choice->{conditions} // [] }) {
                    my ($name, $val) = %$cond;
                    my $spec = $self->conditions_by_pool->{$pool}{$name}
                        or die "choice '$cid' in event '$eid': unknown condition '$name'";
                }
            }
        } else {
            die "event '$eid': must have 'effects'" unless $event->{effects} && @{ $event->{effects} };
        }

        for my $cond (@{ $event->{conditions} // [] }) {
            my ($name, $val) = %$cond;
            my $spec = $self->conditions_by_pool->{$pool}{$name}
                or die "event '$eid': unknown condition '$name'";
            die "event '$eid': condition '$name' may not use ranges"
                if ref $val eq 'ARRAY';
        }

        my %seen_effs;
        for my $eff (@{ $event->{effects} }) {
            my ($name, $val) = %$eff;
            my $spec = $self->effects_by_pool->{$pool}{$name}
                or die "event '$eid': unknown effect '$name'";
            die "event '$eid': duplicate effect '$name'" if $seen_effs{$name}++;
        }
    }

    $self->_loaded_pools->{$pool} = $events;
    return $events;
}

1;
