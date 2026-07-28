use Modern::Perl;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Season;

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

# Seed an existing active season before running create-season --force
MagicMountain::Model::Season->new(file => "$dir/seasons.json")
    ->create(id => 's1', label => 'Season 1', status => 'active', day => 15, length => 30,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 10, artifacts_received => 0,
                intake_by_trait => {}, daily_intake => 0, days_since_purchase => 0 },
        },
    )->save;

my $t = TestEnv->create_app;
my $app = $t->app;

$app->commands->run('create-season', '--force');

$app->seasons->load;
$app->accounts->load;
$app->characters->load;

# Old season archived
my $old = $app->seasons->get('s1');
is $old->getCol('status'), 'archived', 'previous season archived';

# New season created
my $season = $app->active_season;
ok $season, 'new active season exists';
is $season->getCol('day'), 1, 'day is 1';
is $season->getCol('label'), 'Season 2', 'label auto-increments to Season 2';

my @bots = @{ $app->characters->find(sub { $_[0]->{is_bot} }) };
is scalar @bots, 2, '2 bot characters created';

my $accts = $app->accounts->all;
cmp_ok scalar(keys %$accts), '>=', 2, 'bot accounts exist';

done_testing;
