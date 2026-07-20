use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(decode_json);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $svc_token = 'test-bot-token';
write_file("$dataDir/magic_mountain.yml", "---\nbots:\n  count: 1\n  profiles:\n    - id: greed_desperate\n  action_points: 15\nbot_service_token: $svc_token\n");
$ENV{MM_CFG_FILE} = "$dataDir/magic_mountain.yml";

subtest 'bot runs during maintenance, AP consumed, then reset' => sub {
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(
            id            => 's1',
            label         => 'Test Season',
            status        => 'active',
            day           => 3,
            length        => 30,
            faction_state => {},
        )->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $bot_a = $accts->create(username => 'bot-greed_desperate-001');
    $bot_a->save;

    my $human_a = $accts->create(username => 'player');
    $human_a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
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

    MagicMountain::Model::Account->new(file => "$dataDir/sessions.json")->save;

    my $t    = Test::Mojo->new('MagicMountain');
    my $app  = $t->app;
    $app->config->{bot_service_token} = $svc_token;

    my $maint = $app->maintenance;

    $maint->on_maintenance->($maint);

    # Human AP reset
    $app->characters->load;
    my ($human_char) = @{ $app->characters->find(
        sub { $_[0]->{account_id} eq $human_a->getCol('id') }
    ) };
    ok $human_char, 'human character still exists';

    # Day advanced
    my $season = $app->seasons->get('s1');
    is $season->getCol('day'), 4, 'day advanced';
};

done_testing;
