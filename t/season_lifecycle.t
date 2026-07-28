use Modern::Perl;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Season;
use MagicMountain::Model::Account;
use MagicMountain::Service::SeasonManager;

sub _app_with_bots {
    my $count = shift;
    my $dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dir;

    write_file("$dir/config.yml", <<"YAML");
bots:
  count: $count
  profiles:
  - id: stage_guard_opportunist
  - id: fixed_highest
  - id: instability_loyalist
YAML

    $ENV{MM_CFG_FILE} = "$dir/config.yml";
    my $t = TestEnv->create_app;
    return ($t->app, $dir);
}

subtest 'ensureActiveSeason with empty DB seeds bots' => sub {
    my ($app, $dir) = _app_with_bots(3);

    my $season = $app->active_season;
    ok $season, 'active season exists';
    is $season->getCol('day'), 1, 'day is 1';
    is $season->getCol('label'), 'Season 1', 'label is Season 1';

    $app->accounts->load;
    $app->characters->load;

    my @bot_chars = @{ $app->characters->find(sub {
        $_[0]->{is_bot} && $_[0]->{season_id} eq $season->getCol('id')
    }) };
    is scalar @bot_chars, 3, '3 bot characters created by ensureActiveSeason';

    my $accts = $app->accounts->all;
    cmp_ok scalar(keys %$accts), '>=', 3, 'bot accounts exist';
};

subtest 'ensureActiveSeason uses correct label with archived seasons' => sub {
    my $dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dir;
    write_file("$dir/config.yml", "bots:\n  count: 0\n");
    $ENV{MM_CFG_FILE} = "$dir/config.yml";

    my $sm = MagicMountain::Model::Season->new(file => "$dir/seasons.json");
    for my $i (1 .. 2) {
        $sm->create(
            id     => "s$i",
            label  => "Season $i",
            status => 'archived',
            day    => 30,
            length => 30,
        )->save;
    }

    my $t = TestEnv->create_app;
    my $app = $t->app;

    my $season = $app->active_season;
    ok $season, 'active season exists';
    is $season->getCol('label'), 'Season 3', 'label is Season 3 (max+1, not hardcoded 1)';
    is $season->getCol('day'), 1, 'day is 1';
};

subtest 'catch_up_maintenance advances day without off-by-one' => sub {
    my $dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dir;
    write_file("$dir/config.yml", "bots:\n  count: 0\n");
    $ENV{MM_CFG_FILE} = "$dir/config.yml";

    my $now = CORE::time;
    my $sm = MagicMountain::Model::Season->new(file => "$dir/seasons.json");
    $sm->create(
        id               => 's1',
        label            => 'Season 1',
        status           => 'active',
        day              => 23,
        length           => 30,
        last_maintenance => $now,
    )->save;

    my $t = TestEnv->create_app;
    my $app = $t->app;
    my $maint = $app->maintenance;

    # Override clock for deterministic boundary calculation
    $maint->clock(sub { $now });

    my $boundary = $maint->recent_maintenance_boundary;

    # Set last_maintenance to exactly 1 day before boundary
    my $season = $app->active_season;
    $season->setCol('last_maintenance', $boundary - 86400);
    $season->save;

    # Re-run catch-up (startup already ran it with last_maintenance=now, no-op)
    $app->_catch_up_maintenance;

    $app->seasons->load;
    $season = $app->seasons->get('s1');

    # Off-by-one bug: 23 + int(86400/86400) + 1 = 25
    # Correct:        23 + int(86400/86400)     = 24
    is $season->getCol('day'), 24, 'day advanced by exactly 1 (no off-by-one)';
};

subtest 'seed_bots creates correct number of bot characters' => sub {
    my ($app, $dir) = _app_with_bots(0);

    $app->config->{bots} = {
        count    => 2,
        profiles => [
            { id => 'stage_guard_opportunist' },
            { id => 'fixed_highest' },
        ],
    };

    my $season = $app->active_season;
    MagicMountain::Service::SeasonManager->new(app => $app)->seed_bots($season);

    $app->accounts->load;
    $app->characters->load;

    my @bots = @{ $app->characters->find(sub {
        $_[0]->{is_bot} && $_[0]->{season_id} eq $season->getCol('id')
    }) };
    is scalar @bots, 2, '2 bot characters created by seed_bots';

    my $accts = $app->accounts->all;
    cmp_ok scalar(keys %$accts), '>=', 2, 'bot accounts exist';
};

subtest 'SeasonManager::ensure_season creates season with bots and player character' => sub {
    my $dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dir;

    write_file("$dir/config.yml", <<'YAML');
bots:
  count: 2
  profiles:
  - id: stage_guard_opportunist
  - id: fixed_highest
YAML
    $ENV{MM_CFG_FILE} = "$dir/config.yml";

    my $t = TestEnv->create_app;
    my $app = $t->app;

    # Create a player account
    $app->accounts->load;
    my $acct_model = $app->accounts->create(username => 'player');
    $acct_model->save;

    # Archive the active season that startup created
    my $existing = $app->active_season;
    if ($existing) {
        $existing->setCol('status', 'archived');
        $existing->save;
    }

    # Call ensure_season — it should create a new season with bots
    my ($season, $recap) = MagicMountain::Service::SeasonManager->new(app => $app)
        ->ensure_season($acct_model->getCol('id'));

    ok $season, 'ensure_season returned a season';
    is $season->getCol('day'), 1, 'day is 1';

    # Bots exist
    $app->characters->load;
    my @bots = @{ $app->characters->find(sub {
        $_[0]->{is_bot} && $_[0]->{season_id} eq $season->getCol('id')
    }) };
    is scalar @bots, 2, '2 bot characters created by ensure_season';
};

done_testing;
