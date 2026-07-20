use Modern::Perl;
use Test2::V0;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Bot::Agent;

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

sub _make_agent ($;$) {
    my $ua = Mojo::UserAgent->new;
    $ua->server->app($t->app);
    $ua->server->url;
    MagicMountain::Bot::Agent->new(
        ua        => $ua,
        base_url  => $ua->server->url->to_string,
        svc_token => $_[0],
    );
}

sub _make_season_and_char ($) {
    my $player_name = shift;

    $t->app->seasons->load;
    my $season = $t->app->active_season;
    unless ($season) {
        $season = $t->app->seasons->create(
            label         => 'Test',
            status        => 'active',
            day           => 1,
            length        => 30,
            faction_state => {},
        );
        $season->save;
    }

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

subtest 'Agent login succeeds for a new player' => sub {
    my $agent = _make_agent($token);
    my $res = $agent->login('test-agent-player');
    ok $res->{ok}, 'login ok';
    ok $agent->csrf_token, 'csrf_token set';
    is $res->{player}{displayName}, 'test-agent-player', 'player name matches';
};

subtest 'Agent login succeeds for a bot account' => sub {
    my $accts = $t->app->accounts;
    my $chars = $t->app->characters;
    $accts->load;
    $chars->load;

    my $season = $t->app->active_season;
    SKIP: {
        skip 'No active season', 5 unless $season;
        my $a = $accts->create(username => 'test-bot-agent');
        $a->save;

        my $c = $chars->create(
            name              => 'test-bot-agent',
            account_id        => $a->getCol('id'),
            season_id         => $season->getCol('id'),
            is_bot            => 1,
            score             => 0,
            scrap             => 0,
            action_points     => 15,
            action_points_max => 15,
        );
        $c->save;

        my $agent = _make_agent($token);
        my $res = $agent->login('test-bot-agent');
        ok $res->{ok}, 'bot account login ok';
        ok $agent->csrf_token, 'bot account csrf_token set';
        is $res->{player}{displayName}, 'test-bot-agent', 'player name matches';
        $agent->logout;
    }
};

subtest 'Agent login fails without service token for bot accounts' => sub {
    my $accts = $t->app->accounts;
    my $chars = $t->app->characters;
    $accts->load;
    $chars->load;

    my $season = $t->app->active_season;
    SKIP: {
        skip 'No active season', 2 unless $season;
        my $a = $accts->create(username => 'test-bot-blocked');
        $a->save;

        my $c = $chars->create(
            name              => 'test-bot-blocked',
            account_id        => $a->getCol('id'),
            season_id         => $season->getCol('id'),
            is_bot            => 1,
            score             => 0,
            scrap             => 0,
            action_points     => 15,
            action_points_max => 15,
        );
        $c->save;

        my $agent = _make_agent(undef);
        my $err;
        eval { $agent->login('test-bot-blocked') };
        $err = $@;
        like $err, qr/Login failed/, 'bot account login blocked without token';
    }
};

subtest 'Agent game and nav work with season + character' => sub {
    my $agent = _make_agent($token);
    $agent->login('test-full-player');
    _make_season_and_char('test-full-player');

    my $state = $agent->game;
    ok $state->{ok}, 'game endpoint ok';
    ok exists $state->{player}, 'game has player key';
    ok exists $state->{season}, 'game has season key';

    my $nav = $agent->nav;
    ok $nav->{ok}, 'nav endpoint ok';
    ok exists $nav->{primary_tabs}, 'nav has primary_tabs';
};

subtest 'Agent ->req fails on bad endpoints' => sub {
    my $agent = _make_agent($token);
    $agent->login('test-fail-player');

    my $err;
    eval { $agent->req(GET => '/nonexistent') };
    $err = $@;
    like $err, qr/failed/, 'req fails on nonexistent path';
};

done_testing;
