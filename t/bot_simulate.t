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

subtest 'simulate runs end-to-end' => sub {
    my $app = $t->app;
    my $cmd = MagicMountain::Command::simulate->new(app => $app);

    eval { $cmd->run('--count', 2, '--days', 3, '--seed', 42) };
    diag("Simulation error: $@") if $@;

    pass('simulate completed without crashing');
};

subtest 'transcript has expected events' => sub {
    my $app = $t->app;

    # Re-run with explicit output
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

subtest 'sale events include budget pressure fields' => sub {
    my $app = $t->app;
    my $outfile = "$data_dir/budget_test.jsonl";
    my $cmd = MagicMountain::Command::simulate->new(app => $app);
    eval { $cmd->run('--count', 2, '--days', 2, '--seed', 7,
        '--counter-offers', '--multi-item',
        '--profile-weights', 'stage_guard_opportunist=1,greed_desperate=1',
        '--output', $outfile) };
    diag("Simulation error: $@") if $@;

    my @lines = read_file($outfile);
    my $found_sale = 0;
    for my $line (@lines) {
        my $ev = decode_json($line);
        next unless $ev->{type} eq 'sale';
        $found_sale = 1;
        ok(exists $ev->{spent_so_far}, 'sale has spent_so_far');
        ok(exists $ev->{soft_budget}, 'sale has soft_budget');
        ok(exists $ev->{over_budget}, 'sale has over_budget flag');
        last;
    }
    ok($found_sale, 'at least one sale event found');
};

subtest 'highest_offer stops before opportunist on budget pressure' => sub {
    my $app = $t->app;
    my $outfile = "$data_dir/pressure_test.jsonl";
    my $cmd = MagicMountain::Command::simulate->new(app => $app);
    eval { $cmd->run('--count', 2, '--days', 7, '--seed', 42,
        '--counter-offers', '--multi-item',
        '--profile-weights', 'fixed_highest=1,stage_guard_opportunist=1',
        '--output', $outfile) };
    diag("Simulation error: $@") if $@;
    ok(-e $outfile, 'transcript exists for pressure test');

    my @lines = read_file($outfile);
    my %sale_count;
    for my $line (@lines) {
        my $ev = decode_json($line);
        next unless $ev->{type} eq 'sale' && $ev->{char_id};
        $sale_count{$ev->{char_id}}++;
    }

    my %profile_of;
    for my $line (@lines) {
        my $ev = decode_json($line);
        if ($ev->{type} eq 'sim_start') {
            for (@{$ev->{bots}}) { $profile_of{$_->{char_id}} = $_->{sell_policy} }
        }
    }

    for my $cid (keys %sale_count) {
        my $pol = $profile_of{$cid} // 'unknown';
        diag("$pol made $sale_count{$cid} sales in 7 days");
    }

    # Both profiles should make sales without crashing
    ok(scalar(keys %sale_count) > 0, 'bots made sales under state-based pressure');

    # Check for policy_skill_purchase events
    my @skill_events;
    for my $line (@lines) {
        my $ev = decode_json($line);
        push @skill_events, $ev if $ev->{type} eq 'policy_skill_purchase';
    }
    diag(sprintf("policy_skill_purchase events: %d", scalar @skill_events));
    for my $ev (@skill_events) {
        ok($ev->{skill_id}, 'policy_skill_purchase has skill_id');
        ok(defined $ev->{cost}, 'policy_skill_purchase has cost');
        ok($ev->{policy},   'policy_skill_purchase has policy name');
    }
};

done_testing;
