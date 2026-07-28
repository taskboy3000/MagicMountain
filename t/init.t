use Modern::Perl;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

my $dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dir;

write_file("$dir/config.yml", <<'YAML');
bots:
  count: 3
  profiles:
  - id: stage_guard_opportunist
  - id: fixed_highest
  - id: instability_loyalist
YAML
$ENV{MM_CFG_FILE} = "$dir/config.yml";

my $t = TestEnv->create_app;
my $app = $t->app;

$app->commands->run('init', '--force');

$app->seasons->load;
$app->accounts->load;
$app->characters->load;

my $season = $app->active_season;
ok $season, 'active season exists after init';
is $season->getCol('day'), 1, 'day is 1';
is $season->getCol('label'), 'Season 1', 'label is Season 1';

my @bots = @{ $app->characters->find(sub { $_[0]->{is_bot} }) };
is scalar @bots, 3, '3 bot characters created';

my $accts = $app->accounts->all;
cmp_ok scalar(keys %$accts), '>=', 3, 'bot accounts exist';

done_testing;
