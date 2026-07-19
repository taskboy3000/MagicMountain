use Modern::Perl;
use Test2::V0;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Bot::Agent;
use MagicMountain::Bot::Routine;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;
my $token = 'test-bot-token-abc123';
write_file("$dataDir/magic_mountain.yml", <<"YAML");
bots:
  count: 0
bot_service_token: $token
YAML
$ENV{MM_CFG_FILE} = "$dataDir/magic_mountain.yml";

my $t = Test::Mojo->new('MagicMountain');
$t->app->config->{bot_service_token} = $token;

sub _make_agent {
    my $ua = Mojo::UserAgent->new;
    $ua->server->app($t->app);
    $ua->server->url;
    MagicMountain::Bot::Agent->new(
        ua        => $ua,
        base_url  => $ua->server->url->to_string,
        svc_token => $token,
    );
}

sub _ensure_season_and_char ($) {
    my $player_name = shift;
    $t->app->seasons->load;
    my $season = $t->app->active_season;
    return unless $season;

    $t->app->accounts->load;
    $t->app->characters->load;
    my ($acct) = @{ $t->app->accounts->find(sub { $_[0]->{username} eq $player_name }) };
    return unless $acct;

    my $season_id = $season->getCol('id');
    my ($existing) = @{ $t->app->characters->find(sub {
        $_[0]->{account_id} eq $acct->getCol('id') && $_[0]->{season_id} eq $season_id
    }) };
    return if $existing;

    my $c = $t->app->characters->create(
        name              => $player_name,
        account_id        => $acct->getCol('id'),
        season_id         => $season_id,
        score             => 0,
        scrap             => 150,
        action_points     => 15,
        action_points_max => 15,
    );
    $c->save;
}

subtest 'Routine runs a full prospecting cycle' => sub {
    my $agent = _make_agent;
    $agent->login('test-prospect');
    _ensure_season_and_char('test-prospect');

    my $routine = MagicMountain::Bot::Routine->new(agent => $agent);

    my $profile = {
        id          => 'test_prospect',
        push_policy => { name => 'fixed_pushes', params => { max => 2 } },
        sell_policy => { name => 'opportunist', params => {} },
        skill_policy => { name => 'never' },
    };

    my $result = $routine->run_day($profile);
    ok $result->{ok}, 'routine run_day ok';
    ok exists $result->{actions}, 'actions tracked';
    cmp_ok $result->{actions}, '>', 0, 'some actions performed';
};

subtest 'Routine with different push policy' => sub {
    my $agent = _make_agent;
    $agent->login('test-push-policy');
    _ensure_season_and_char('test-push-policy');

    my $routine = MagicMountain::Bot::Routine->new(agent => $agent);

    my $profile = {
        id          => 'test_push_policy',
        push_policy => { name => 'stage_guard', params => { stop_at => 'strained' } },
        sell_policy => { name => 'opportunist', params => {} },
        skill_policy => { name => 'never' },
    };

    my $result = $routine->run_day($profile);
    ok $result->{ok}, 'push profile run_day ok';
    ok $result->{actions} > 0, 'actions performed with push policy';
};

subtest 'Routine handles invalid profile' => sub {
    my $agent = _make_agent;
    my $routine = MagicMountain::Bot::Routine->new(agent => $agent);

    my $result = $routine->run_day;
    ok !$result->{ok}, 'run_day fails without profile';
    is $result->{error}, 'No bot profile', 'correct error message';
};

done_testing;
