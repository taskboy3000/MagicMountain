## no critic

use Modern::Perl;
use Test::More;
use POSIX qw(mktime);
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Maintenance;

package FakeLogger;
sub new   { bless { messages => [] }, shift }
sub debug { my $self = shift; push @{$self->{messages}}, [debug => @_] }
sub info  { my $self = shift; push @{$self->{messages}}, [info => @_] }
sub warn  { my $self = shift; push @{$self->{messages}}, [warn  => @_] }


package FakeDailyMaintenance;
sub new { bless { app => $_[1] }, shift }
sub open_bot_window { 0 }
sub app { $_[0]->{app} }

package FakeApp;
sub new {
    my $self = bless {
        log               => FakeLogger->new,
        dataDir           => File::Temp::tempdir(CLEANUP => 1),
        config            => { bots => { count => 0 }, maintenance_bot_deadline_minutes => 10 },
    }, shift;
    $self->{daily_maintenance} = FakeDailyMaintenance->new($self);
    return $self;
}
sub log { shift->{log} }
sub transcript { bless {}, 'FakeTranscript' }
sub dataDir { shift->{dataDir} }
sub config { shift->{config} }
sub daily_maintenance { shift->{daily_maintenance} }
sub characters {
    no warnings 'once';
    state $chars = do {
        package FakeChars;
        sub new { bless {}, shift }
        sub find { [] }
    };
    FakeChars->new;
}



package FakeTranscript;
sub log_event { 1 }

package main;

my $app = FakeApp->new;

my $end_of_day_hour = 12;

my @today = (0, 0, $end_of_day_hour, 15, 5, 2024 - 1900, 0, 0, -1);
my $today_noon  = mktime(@today);
my $before_noon = $today_noon - 3600;
my $after_noon  = $today_noon + 3600;

my @tomorrow = @today;
$tomorrow[3]++;
my $tomorrow_noon = mktime(@tomorrow);

my @day_after = @tomorrow;
$day_after[3]++;
my $day_after_noon = mktime(@day_after);

subtest 'before deadline — does not fire' => sub {
    my $clock = sub { $before_noon };
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
    );
    ok !$maint->dailyMaintenance, 'returns false when before deadline';
    ok !$maint->in_maintenance,   'in_maintenance stays false';
};

subtest 'at deadline — fires, in_maintenance was true' => sub {
    my $clock  = sub { $today_noon };
    my $caught = 0;
    my $maint  = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
        on_maintenance  => sub {
            $caught = $_[0]->in_maintenance;
        },
    );
    my $result = $maint->dailyMaintenance;
    ok $result,                    'returns true at deadline';
    ok $caught,                    'in_maintenance was true during callback';
    ok !$maint->in_maintenance,    'in_maintenance cleared after';
    cmp_ok $maint->next_run, '>=', $tomorrow_noon,
        'next_run advanced to next day';
};

subtest 'same day, already ran — does not fire again' => sub {
    my $clock = sub { $after_noon };
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
    );
    $maint->next_run($tomorrow_noon);
    ok !$maint->dailyMaintenance, 'returns false after already ran today';
};

subtest 'next day at deadline — fires again' => sub {
    my $clock = sub { $tomorrow_noon };
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
    );
    my $result = $maint->dailyMaintenance;
    ok $result, 'returns true at next day deadline';
    ok !$maint->in_maintenance, 'in_maintenance cleared after';
    cmp_ok $maint->next_run, '>=', $day_after_noon,
        'next_run advanced to day after tomorrow';
};

subtest 'mark_bot_window_open records opened_at and rollover resets it' => sub {
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => sub { $today_noon },
    );
    $maint->mark_bot_window_open;
    ok $maint->bot_window_open, 'window open after mark';
    is $maint->bot_window_opened_at, $today_noon, 'opened_at recorded from clock';
    $maint->_rollover;
    ok !$maint->bot_window_open,           'window closed by rollover';
    is $maint->bot_window_opened_at, 0,    'opened_at reset by rollover';
};

subtest 'window open within deadline — stays open' => sub {
    my $now   = $today_noon + 60;
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => sub { $now },
    );
    $maint->next_run($before_noon);
    $maint->mark_bot_window_open;
    ok !$maint->dailyMaintenance, 'returns false while window open';
    ok $maint->bot_window_open,   'window stays open before deadline';
    is $maint->bot_window_opened_at, $now, 'opened_at unchanged';
};

subtest 'window open past deadline — watchdog force-closes' => sub {
    my $now   = $today_noon;
    my $clock = sub { $now };
    my $caught = 0;
    my $maint  = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
        on_maintenance  => sub { $caught = $_[0]->in_maintenance },
    );
    $maint->next_run($tomorrow_noon);
    $maint->mark_bot_window_open;
    $now = $today_noon + 600;
    ok $maint->dailyMaintenance,  'watchdog returns true past deadline';
    ok !$maint->bot_window_open,  'window force-closed by watchdog';
    is $maint->bot_window_opened_at, 0, 'opened_at reset';
    ok $caught, 'maintenance ran (in_maintenance true during callback)';
};

subtest 'after watchdog close — next tick does not re-open' => sub {
    my $now   = $today_noon;
    my $clock = sub { $now };
    my $maint = MagicMountain::Maintenance->new(
        app             => $app,
        end_of_day_hour => $end_of_day_hour,
        clock           => $clock,
    );
    $maint->next_run($tomorrow_noon);
    $maint->mark_bot_window_open;
    $now += 600;
    ok $maint->dailyMaintenance, 'watchdog force-closes overdue window';
    ok !$maint->bot_window_open, 'window closed';
    ok !$maint->dailyMaintenance,    'subsequent tick gated by next_run';
    ok !$maint->bot_window_open, 'still closed, no re-open';
};

done_testing;
