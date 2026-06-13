package MagicMountain::Maintenance;

use Mojo::Base '-base', '-signatures';
use POSIX qw(strftime mktime);

has app             => sub { die "app is required" };
has end_of_day_hour => 0;
has clock           => sub { \&CORE::time };
has on_maintenance  => sub { sub {} };

has next_run => sub ($self) {
    my $nextWindow = $self->compute_next_maintenance_window;
    $self->app->log->debug("Next daily maintenance window: " . localtime($nextWindow));
    return $nextWindow;
};

has in_maintenance => 0;

sub compute_next_maintenance_window ($self, $timestamp = undef) {
    $timestamp //= $self->clock->();

    my @tm = localtime($timestamp);
    $tm[0] = 0;                       # sec
    $tm[1] = 0;                       # min
    $tm[2] = $self->end_of_day_hour;  # hour
    $tm[8] = -1;                      # isdst unknown, let libc decide

    my $candidate = mktime(@tm);

    if ($candidate < $timestamp) {
        $tm[3]++;                     # mday — mktime normalizes overflow
        $candidate = mktime(@tm);
    }

    return $candidate;
}

sub dailyMaintenance ($self) {
    my $now = $self->clock->();
    return if $self->next_run > $now;

    $self->in_maintenance(1);
    $self->app->log->debug("Daily maintenance started");

    $self->next_run($self->compute_next_maintenance_window($now + 1));

    $self->app->log->debug("Next daily maintenance window: " . localtime($self->next_run));

    $self->on_maintenance->($self);
    $self->in_maintenance(0);
    return 1;
}

1;
