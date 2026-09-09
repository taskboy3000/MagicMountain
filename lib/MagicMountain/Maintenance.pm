package MagicMountain::Maintenance;

use File::Basename;
use File::Copy;
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
has bot_window_open => 0;
has bot_window_opened_at => 0;
has _catching_up => 0;

sub catch_up ($self, $missed_cycles) {
    $self->in_maintenance(1);
    $self->_catching_up(1);
    for (1 .. $missed_cycles) {
        $self->on_maintenance->($self);
    }
    $self->_catching_up(0);
    $self->in_maintenance(0);
}

sub recent_maintenance_boundary ($self, $timestamp = undef) {
    $timestamp //= $self->clock->();
    my $boundary = $self->compute_next_maintenance_window($timestamp);
    $boundary -= 86400;
    return $boundary;
}

sub compute_next_maintenance_window ($self, $timestamp = undef) {
    $timestamp //= $self->clock->();

    my @tm = localtime($timestamp);
    $tm[0] = 0;
    $tm[1] = 0;
    $tm[2] = $self->end_of_day_hour;
    $tm[8] = -1;

    my $candidate = mktime(@tm);

    if ($candidate < $timestamp) {
        $tm[3]++;
        $candidate = mktime(@tm);
    }

    return $candidate;
}

sub _backup_data ($self) {
    my $backup_dir = $self->app->dataDir . '/backups';
    my $ts = strftime('%Y%m%d_%H%M%S', gmtime);
    my $day_dir = "$backup_dir/" . strftime('%Y-%m-%d', gmtime);
    mkdir $backup_dir unless -d $backup_dir;
    mkdir $day_dir unless -d $day_dir;
    for my $f (glob $self->app->dataDir . '/*.json') {
        my $base = (fileparse($f, '.json'))[0];
        copy($f, "$day_dir/${base}.$ts.json")
            or warn "backup failed: $f: $!";
    }
}

sub bot_window_deadline_seconds ($self) {
    my $minutes = $self->app->config->{maintenance_bot_deadline_minutes};
    $minutes = 10 unless defined $minutes;
    return $minutes * 60;
}

sub mark_bot_window_open ($self) {
    $self->bot_window_open(1);
    $self->bot_window_opened_at($self->clock->());
    return 1;
}

sub _rollover ($self) {
    return if $self->bot_window_open == 0;

    $self->bot_window_open(0);
    $self->bot_window_opened_at(0);

    $self->_backup_data;

    $self->in_maintenance(1);
    $self->app->log->debug("Daily maintenance rollover started");

    $self->on_maintenance->($self);

    $self->in_maintenance(0);
    $self->app->log->debug("Daily maintenance rollover complete");
    return 1;
}

sub _do_rollover ($self) {
    $self->next_run($self->compute_next_maintenance_window(CORE::time + 1));
    $self->app->log->debug("Next daily maintenance window: " . localtime($self->next_run));

    my $opened = $self->app->daily_maintenance->open_bot_window($self);
    if (!$opened) {
        $self->mark_bot_window_open;
        $self->_rollover;
    }
    return 1;
}
sub dailyMaintenance ($self) {
    my $now = $self->clock->();

    if ($self->bot_window_open) {
        # Watchdog: if the window has been open past the deadline without a
        # completion callback, the subprocess signal was lost. Force-close
        # regardless so a stalled bot turn can never wedge the server. This
        # check must precede the next_run gate so it fires on every tick even
        # though next_run was already advanced when the window opened.
        my $opened = $self->bot_window_opened_at || 0;
        if ($opened > 0 && $now - $opened >= $self->bot_window_deadline_seconds) {
            $self->app->log->warn(sprintf(
                "Bot window open %ds without completion — force-closing",
                $now - $opened,
            ));
            return $self->_rollover;
        }
        return;
    }

    return if $self->next_run > $now;

    $self->app->log->debug("Daily maintenance window opening");
    return $self->_do_rollover;
}

1;
