use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file read_file);
use Mojo::JSON qw(decode_json);

use_ok('MagicMountain::Command::simulate');

# Run a short simulation and verify the transcript
my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

# Use the Mojo test app to simulate
use Test::Mojo;
my $t = Test::Mojo->new('MagicMountain');
$t->app->config->{bot_service_token} //= 'sim-test-token';

subtest 'simulate runs end-to-end' => sub {
    my $app = $t->app;
    my $cmd = MagicMountain::Command::simulate->new(app => $app);

    eval { $cmd->run('--count', 2, '--days', 3, '--seed', 42) };
    diag("Simulation error: $@") if $@;

    pass('simulate completed without crashing');
};

subtest 'transcript has expected events' => sub {
    my $app = $t->app;

    my $outfile = "$data_dir/out.jsonl";
    my $cmd = MagicMountain::Command::simulate->new(app => $app);
    eval { $cmd->run('--count', 2, '--days', 3, '--seed', 99, '--output', $outfile) };
    diag("Simulation error: $@") if $@;

    ok(-e $outfile, 'transcript file exists');
    my @lines = read_file($outfile);
    cmp_ok(scalar @lines, '>=', 2, 'at least sim_start and sim_end events');

    my $first = decode_json($lines[0]);
    is($first->{type}, 'sim_start', 'first event is sim_start');
    ok($first->{narrative}, 'narrative present');

    my $last = decode_json($lines[-1]);
    is($last->{type}, 'sim_end', 'last event is sim_end');

    # Check for game events
    my %types;
    for my $line (@lines) {
        my $ev = decode_json($line);
        $types{$ev->{type}}++;
    }
    ok($types{artifact_start}, 'artifact_start events logged');
    ok($types{push},          'push events logged');
    ok($types{sim_start},     'sim_start logged');
    ok($types{sim_end},       'sim_end logged');
};

subtest 'maintenance ran during simulation' => sub {
    my $app = $t->app;
    my $outfile = "$data_dir/maint_test.jsonl";
    my $cmd = MagicMountain::Command::simulate->new(app => $app);
    eval { $cmd->run('--count', 2, '--days', 5, '--seed', 17, '--output', $outfile) };
    diag("Simulation error: $@") if $@;

    my @lines = read_file($outfile);
    my $snapshot_count = 0;
    for my $line (@lines) {
        my $ev = decode_json($line);
        $snapshot_count++ if ($ev->{type} // '') eq 'faction_snapshot';
    }
    cmp_ok $snapshot_count, '==', 4,
        '4 maintenance cycles for a 5-day simulation';
};

done_testing;
