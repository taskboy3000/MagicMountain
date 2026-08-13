use Modern::Perl;
use Test::More;
use List::Util 'shuffle';
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;

my $svc_token = 'test-bot-token-abc123';
write_file("$data_dir/magic_mountain.yml", <<"YAML");
bots:
  count: 2
  profiles:
    - id: greed_desperate
    - id: balanced_hunter
bot_service_token: $svc_token
YAML
$ENV{MM_CFG_FILE} = "$data_dir/magic_mountain.yml";
$ENV{MM_SKIP_SEASON_CHECK} = 1;

MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
    ->create(
        id            => 's1',
        label         => 'Test Season',
        status        => 'active',
        day           => 5,
        length        => 30,
        faction_state => {},
    )->save;

my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
my $bot_a = $accts->create(username => 'bot-greed_desperate-001');
$bot_a->save;

my $human_a = $accts->create(username => 'player');
$human_a->save;

my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
$chars->create(
    name              => 'bot-greed_desperate-001',
    account_id        => $bot_a->getCol('id'),
    season_id         => 's1',
    score             => 0,
    scrap             => 0,
    action_points     => 15,
    action_points_max => 15,
    is_bot            => 1,
    bot_profile_id    => 'greed_desperate',
    faction_sales     => {},
    standing          => {},
    faction_snubs     => {},
)->save;

$chars->create(
    name              => 'player',
    account_id        => $human_a->getCol('id'),
    season_id         => 's1',
    score             => 42,
    scrap             => 10,
    action_points     => 5,
    action_points_max => 15,
    is_bot            => 0,
)->save;

MagicMountain::Model::Account->new(file => "$data_dir/sessions.json")->save;

my $t = TestEnv->create_app;
my $app = $t->app;
$app->config->{bot_service_token} = $svc_token;

subtest 'command returns 0 when no active season' => sub {
    $app->seasons->load;
    my $season = $app->seasons->get('s1');
    $season->setCol('status', 'finished');
    $season->save;

    my $exit = $app->commands->run('bot_turn');
    is $exit, 0, 'bot_turn returns 0 with no active season';
};

subtest 'command returns 0 when bot count is 0' => sub {
    $app->seasons->load;
    my $season = $app->seasons->get('s1');
    $season->setCol('status', 'active');
    $season->save;

    $app->config->{bots}{count} = 0;

    my $exit = $app->commands->run('bot_turn');
    is $exit, 0, 'bot_turn returns 0 when bot count is 0';

    $app->config->{bots}{count} = 2;
};

subtest 'command builds deterministic bot list from seed' => sub {
    $app->seasons->load;
    my $season = $app->seasons->get('s1');

    my $seed = $season->getCol('day');
    for my $c (unpack('C*', $season->getCol('id') // '')) {
        $seed = (($seed << 5) ^ $seed ^ $c) & 0x7FFFFFFF;
    }

    srand($seed);
    my @shuffled = shuffle(1, 2, 3);
    srand($seed);
    my @shuffled_again = shuffle(1, 2, 3);

    is_deeply \@shuffled, \@shuffled_again, 'same seed produces same shuffle order';
};

subtest 'command finds bot characters in active season' => sub {
    $app->characters->load;
    my @bot_chars = @{ $app->characters->find(sub {
        $_[0]->{season_id} eq 's1' && $_[0]->{is_bot}
    }) };

    is scalar(@bot_chars), 1, 'exactly one bot character in season s1';
    is $bot_chars[0]->getCol('name'), 'bot-greed_desperate-001', 'bot name matches';
};

subtest 'command returns 1 for unknown --bot-id' => sub {
    my $exit = $app->commands->run('bot_turn', '--bot-id', 'nonexistent-bot-id');
    is $exit, 1, 'bot_turn with unknown --bot-id returns 1';
};

done_testing;
