use Modern::Perl;
use Test::More;
use POSIX qw(mktime);
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Maintenance;

{
    package FakeLogger;
    sub new   { bless { messages => [] }, shift }
    sub debug { my $self = shift; push @{$self->{messages}}, [debug => @_] }
    sub info  { my $self = shift; push @{$self->{messages}}, [info => @_] }
}

{
    package FakeApp;
    sub new { bless { log => FakeLogger->new, dataDir => File::Temp::tempdir(CLEANUP => 1) }, shift }
    sub log { shift->{log} }
    sub transcript { bless {}, 'FakeTranscript' }
    sub dataDir { shift->{dataDir} }
}

{
    package FakeTranscript;
    sub log_event { 1 }
}

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

done_testing;
