package MagicMountain::RateLimiter;
use Mojo::Base '-base', '-signatures';

has max_attempts          => 5;
has max_attempts_per_name => 5;
has window_minutes        => 15;
has block_minutes         => 15;

my %attempts;
my %attempts_by_name;

sub time_func ($self) {
    return $self->{time_func}->() if ref $self->{time_func} eq 'CODE';
    return time;
}

sub check ($self, $ip) {
    my $entry = $attempts{$ip} or return 1;
    my $now = $self->time_func;

    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $attempts{$ip};
        return 1;
    }

    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        delete $attempts{$ip};
        return 1;
    }

    return 1;
}

sub record_failure ($self, $ip) {
    my $now = $self->time_func;
    my $entry = $attempts{$ip} //= { count => 0, first_attempt => $now };

    return $entry->{count} if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $entry->{blocked_until};
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }

    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }

    $entry->{count}++;

    if ($entry->{count} >= $self->max_attempts) {
        $entry->{blocked_until} = $now + ($self->block_minutes * 60);
    }

    return $entry->{count};
}

sub record_success ($self, $ip) {
    delete $attempts{$ip};
}

sub check_name ($self, $name) {
    my $entry = $attempts_by_name{$name} or return 1;
    my $now = $self->time_func;

    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $attempts_by_name{$name};
        return 1;
    }

    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        delete $attempts_by_name{$name};
        return 1;
    }

    return 1;
}

sub record_name_failure ($self, $name) {
    my $now = $self->time_func;
    my $entry = $attempts_by_name{$name} //= { count => 0, first_attempt => $now };

    return $entry->{count} if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $entry->{blocked_until};
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }

    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }

    $entry->{count}++;

    if ($entry->{count} >= $self->max_attempts_per_name) {
        $entry->{blocked_until} = $now + ($self->block_minutes * 60);
    }

    return $entry->{count};
}

sub record_name_success ($self, $name) {
    delete $attempts_by_name{$name};
}

sub get_remaining ($self, $ip) {
    my $entry = $attempts{$ip} or return $self->max_attempts;
    my $now = $self->time_func;

    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    return $self->max_attempts if $now - $entry->{first_attempt} > $self->window_minutes * 60;

    return $self->max_attempts - $entry->{count};
}

sub get_name_remaining ($self, $name) {
    my $entry = $attempts_by_name{$name} or return $self->max_attempts_per_name;
    my $now = $self->time_func;

    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    return $self->max_attempts_per_name if $now - $entry->{first_attempt} > $self->window_minutes * 60;

    return $self->max_attempts_per_name - $entry->{count};
}

sub get_reset_time ($self, $ip) {
    my $entry = $attempts{$ip} or return 0;
    my $now = $self->time_func;

    return $entry->{blocked_until} - $now if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    my $window_end = $entry->{first_attempt} + ($self->window_minutes * 60);
    return $window_end > $now ? $window_end - $now : 0;
}

sub get_name_reset_time ($self, $name) {
    my $entry = $attempts_by_name{$name} or return 0;
    my $now = $self->time_func;

    return $entry->{blocked_until} - $now if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    my $window_end = $entry->{first_attempt} + ($self->window_minutes * 60);
    return $window_end > $now ? $window_end - $now : 0;
}

sub cleanup ($self) {
    my $now = $self->time_func;
    for my $key (keys %attempts) {
        my $e = $attempts{$key};
        if (defined $e->{blocked_until} && $now >= $e->{blocked_until}) {
            delete $attempts{$key};
        }
        elsif (!$e->{blocked_until} && $now - $e->{first_attempt} > $self->window_minutes * 60) {
            delete $attempts{$key};
        }
    }
    for my $name (keys %attempts_by_name) {
        my $e = $attempts_by_name{$name};
        if (defined $e->{blocked_until} && $now >= $e->{blocked_until}) {
            delete $attempts_by_name{$name};
        }
        elsif (!$e->{blocked_until} && $now - $e->{first_attempt} > $self->window_minutes * 60) {
            delete $attempts_by_name{$name};
        }
    }
}

1;
