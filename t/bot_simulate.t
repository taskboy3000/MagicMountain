use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file read_file);
use Mojo::JSON qw(decode_json);
use YAML::XS qw(Dump);

use_ok('MagicMountain::Command::simulate');

# Self-contained bot profiles — never load from live content/bots.yml.
my @TEST_PROFILES = (
    {
        id           => 'test_push',
        display_name => 'Test Pusher',
        push_policy  => { name => 'fixed_pushes', params => { max => 3 } },
        sell_policy  => { name => 'opportunist', params => {} },
        skill_policy => { name => 'never' },
    },
    {
        id           => 'test_greed',
        display_name => 'Test Greedy',
        push_policy  => { name => 'greed', params => { prob => 0.9 } },
        sell_policy  => { name => 'desperate', params => {} },
        skill_policy => { name => 'never' },
    },
);

# Each subtest creates its own app + data dir to prevent state leakage
# between simulations (the simulate command rewrites all model files).
sub _run_sim {
    my ($app, $outfile, %opts) = @_;
    my @args;
    push @args, '--count',   $opts{count} // 2;
    push @args, '--days',    $opts{days}  // 3;
    push @args, '--seed',    $opts{seed};
    push @args, '--output',  $outfile if $outfile;
    push @args, '--profile', $opts{profile_file};
    my $cmd = MagicMountain::Command::simulate->new(app => $app);
    eval { $cmd->run(@args) };
    diag("Simulation error: $@") if $@;
}

sub _make_app {
    my $data_dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $data_dir;
    $ENV{MM_SKIP_SEASON_CHECK} = 1;
    my $pf = "$data_dir/profiles.yml";
    write_file($pf, Dump(\@TEST_PROFILES));
    use Test::Mojo;
    my $t = TestEnv->create_app;
    $t->app->config->{bot_service_token} //= 'sim-test-token';
    return ($t->app, $data_dir, $pf);
}

subtest 'simulate runs end-to-end' => sub {
    my ($app, undef, $pf) = _make_app;
    _run_sim($app, undef, count => 2, days => 3, seed => 42, profile_file => $pf);
    pass('simulate completed without crashing');
};

subtest 'transcript has expected events' => sub {
    my ($app, $data_dir, $pf) = _make_app;
    my $outfile = "$data_dir/out.jsonl";

    _run_sim($app, $outfile, count => 2, days => 3, seed => 99, profile_file => $pf);

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
        $types{_count}++;
    }
    diag("Transcript events: " . join(", ", map { "$_=$types{$_}" } sort keys %types));
    ok($types{artifact_start}, 'artifact_start events logged');
    ok($types{push},          'push events logged');
    ok($types{sim_start},     'sim_start logged');
    ok($types{sim_end},       'sim_end logged');
};

subtest 'maintenance ran during simulation' => sub {
    my ($app, $data_dir, $pf) = _make_app;
    my $outfile = "$data_dir/maint_test.jsonl";

    _run_sim($app, $outfile, count => 2, days => 5, seed => 17, profile_file => $pf);

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
