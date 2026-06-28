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
    market_visit => {},
    global      => {},
} };

# ── Effect registries (pool-specific) ───────────────────────────────

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
    market_visit => {},
    global      => {},
} };

# ── Internal state ───────────────────────────────────────────────────

has _loaded_pools => sub { {} };

# ── Public API ───────────────────────────────────────────────────────

sub draw ($self, %args) {
    my $pool    = $args{pool}    or die "pool required";
    my $trigger = $args{trigger} or die "trigger required";
    my $rng     = $args{seeded_rng};

    return undef if $self->app && $self->app->mode eq 'test' && !$ENV{MM_EVENTS};

    my $chance = $self->event_chance->{$pool}{$trigger} // return undef;

    my $roll = $rng ? $rng->() : rand();
    return undef if $roll >= $chance;

    my $ctx = $args{context} // {};

    my $event_def = $self->_select($pool, $trigger, $ctx);
    return undef unless $event_def;

    for my $eff (@{ $event_def->{effects} // [] }) {
        my ($name, $raw) = %$eff;
        my $spec = $self->effects_by_pool->{$pool}{$name}
            or die "handler '$name' not registered for pool '$pool'";
        my $val = $self->_resolve_value($raw, $spec, $rng);
        $spec->{handler}->($ctx, $val);
    }

    return {
        id   => $event_def->{id},
        text => $event_def->{text},
    };
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
        push @candidates, $event;
    }

    return undef unless @candidates;

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
    return $self->_load($pool);
}

sub _load ($self, $pool) {
    my $file = $self->app->home . "/content/events/$pool.yml";
    return [] unless -f $file;

    my $yaml = LoadFile($file);
    die "$pool events must be an array" unless ref $yaml eq 'ARRAY';

    my %seen_ids;
    for my $event (@$yaml) {
        my $eid = $event->{id} // 'UNDEFINED';
        die "event '$eid': must have 'id'" unless defined $event->{id};
        die "event '$eid': id must be ^[a-z][a-z0-9_]*\$" unless $event->{id} =~ /^[a-z][a-z0-9_]*$/;
        die "duplicate event id '$eid'" if $seen_ids{$eid}++;

        die "event '$eid': must have 'trigger'" unless defined $event->{trigger};
        die "event '$eid': trigger must be 'begin'" unless $event->{trigger} eq 'begin';
        die "event '$eid': must have 'weight'" unless defined $event->{weight};
        die "event '$eid': weight must be positive integer"
            unless $event->{weight} =~ /^\d+$/ && $event->{weight} > 0;
        die "event '$eid': must have 'text'" unless defined $event->{text} && length($event->{text}) > 0;

        die "event '$eid': min_day > max_day"
            if defined($event->{min_day}) && defined($event->{max_day}) && $event->{min_day} > $event->{max_day};

        die "event '$eid': must have 'effects'" unless $event->{effects} && @{ $event->{effects} };
        die "event '$eid': choices not supported in v1" if $event->{choices};

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

    $self->_loaded_pools->{$pool} = $yaml;
    return $yaml;
}

1;
