package MagicMountain::Crier;
use Mojo::Base '-base', '-signatures';
use YAML::XS qw(LoadFile);

has content_file => sub { die "content_file is required" };
has log          => sub { sub {} };

my %PRIORITY = (
    faction_dominance => 5,
    faction_surge     => 4,
    milestone         => 3,
    faction_slump     => 2,
    season_opening    => 1,
    daily_progress    => 0.5,
    generic           => 0,
);

sub _load_messages ($self) {
    state $cache = {};
    my $file = $self->content_file;
    return $cache->{$file} //= do {
        my $data = LoadFile($file);
        $data->{crier_messages} // {};
    };
}

sub _pick ($self, $category, $params) {
    my $messages = $self->_load_messages->{$category} or return;
    my $text = $messages->[ int(rand(scalar @$messages)) ] or return;
    $text =~ s!\{(\w+)\}!$params->{$1} // "{$1}"!ge;
    return $text;
}

sub generate ($self, $season, $opts = {}) {
    if ($opts->{time_warp}) {
        return $self->_pick('time_warp', {})
            // $self->_pick('generic', {});
    }

    my $current  = $season->getCol('faction_state') // {};
    my $snapshot = $season->getCol('crier_snapshot') // {};
    my $day      = $season->getCol('day') // 1;
    my $length   = $season->getCol('length') // 30;

    if ($day <= 1 || !keys %$current) {
        return $self->_pick('season_opening', {})
            // $self->_pick('generic', {});
    }

    my %faction_names;
    for my $fid (keys %$current) {
        $faction_names{$fid} = $current->{$fid}{name} // $fid;
    }

    my $max_influence = 0;
    my $leader_id;
    for my $fid (keys %$current) {
        my $inf = $current->{$fid}{influence} // 0;
        if ($inf > $max_influence) {
            $max_influence = $inf;
            $leader_id = $fid;
        }
    }

    my $prev_max = 0;
    my $prev_leader;
    for my $fid (keys %$snapshot) {
        my $inf = $snapshot->{$fid}{influence} // 0;
        if ($inf > $prev_max || !defined $prev_leader) {
            $prev_max = $inf;
            $prev_leader = $fid;
        }
    }

    my $best_priority = -1;
    my $best_message;

    for my $fid (keys %$current) {
        my $cur  = $current->{$fid};
        my $prev = $snapshot->{$fid} // {};
        my $inf_gain   = ($cur->{influence} // 0) - ($prev->{influence} // 0);
        my $recv       = $cur->{artifacts_received} // 0;
        my $prev_recv  = $prev->{artifacts_received} // 0;
        my $fname      = $faction_names{$fid};

        my $msg;

        if ($fid eq $leader_id && (!defined $prev_leader || $leader_id ne $prev_leader)) {
            $msg = $self->_pick('faction_dominance', {
                faction => $fname, influence => $cur->{influence} // 0,
            });
            _consider($msg, 'faction_dominance', \$best_priority, \$best_message);
        }

        if ($inf_gain > 0) {
            $msg = $self->_pick('faction_surge', {
                faction => $fname, influence_gain => $inf_gain, count => $recv,
            });
            _consider($msg, 'faction_surge', \$best_priority, \$best_message);
        }

        my $threshold = 10;
        while ($threshold <= 100) {
            if ($prev_recv < $threshold && $recv >= $threshold) {
                $msg = $self->_pick('milestone', {
                    faction => $fname, count => $recv,
                });
                _consider($msg, 'milestone', \$best_priority, \$best_message);
                last;
            }
            $threshold = int($threshold * 2.5 + 0.5);
        }

        if ($inf_gain == 0 && $prev_recv > 0) {
            $msg = $self->_pick('faction_slump', {
                faction => $fname, count => $recv,
            });
            _consider($msg, 'faction_slump', \$best_priority, \$best_message);
        }
    }

    return $best_message if $best_message;
    my $daily = $self->_pick_daily($day, $length);
    return $daily if $daily;
    return $self->_pick('generic', {});
}

sub _pick_daily ($self, $day, $length) {
    my $buckets = $self->_load_messages->{daily_progress} or return;
    my $ratio   = $length > 0 ? $day / $length : 0;
    for my $b (@$buckets) {
        next if exists $b->{day_max_pct} && $ratio > $b->{day_max_pct};
        next if exists $b->{day_min_pct} && $ratio < $b->{day_min_pct};
        next if exists $b->{day_max}      && $day    > $b->{day_max};
        next if exists $b->{day_min}      && $day    < $b->{day_min};
        my $msgs = $b->{messages} or next;
        return $msgs->[ int(rand(scalar @$msgs)) ];
    }
    return;
}

sub _consider ($msg, $category, $best_prio_ref, $best_msg_ref) {
    return unless $msg;
    my $prio = $PRIORITY{$category} // 0;
    if ($prio > $$best_prio_ref) {
        $$best_prio_ref = $prio;
        $$best_msg_ref  = $msg;
    }
}

1;
