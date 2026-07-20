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

subtest 'Routine pawn phase processes banned items' => sub {
    my $agent = _make_agent;
    $agent->login('test-pawn-routine');
    _ensure_season_and_char('test-pawn-routine');

    my $season = $t->app->active_season;
    SKIP: {
        skip 'No active season', 4 unless $season;

        $season->setCol('faction_climate', {
            banned_traits => ['illicit'],
            market => { buyer_trait_biases => {} },
        });
        $season->save;

        $t->app->shed->load;
        my $char;
        $t->app->characters->load;
        ($char) = @{ $t->app->characters->find(sub { $_[0]->{name} eq 'test-pawn-routine' }) };
        skip 'No character', 4 unless $char;

        $char->setCol('action_points', 15);
        $char->setCol('scrap', 50);
        $char->save;

        my $item = $t->app->shed->create(
            char_id       => $char->getCol('id'),
            artifact_id   => 'pawn_test_art',
            original_value => 30,
            decayed_value  => 20,
            behaviors     => ['illicit'],
            condition     => 'fair',
        );
        $item->save;

        my @transcript;
        my $routine = MagicMountain::Bot::Routine->new(
            agent      => $agent,
            transcript_cb => sub { push @transcript, $_[0] },
        );

        my $profile = {
            id           => 'test_pawn',
            push_policy  => { name => 'fixed_pushes', params => { max => 1 } },
            sell_policy  => { name => 'opportunist', params => {} },
            pawn_policy  => { name => 'always' },
            skill_policy => { name => 'never' },
        };

        my $result = $routine->run_day($profile);
        ok $result->{ok}, 'run_day ok with pawn';

        my @pawn_logs = grep { $_->{type} eq 'offer_pawn' } @transcript;
        cmp_ok scalar(@pawn_logs), '>', 0, 'pawn offers were made';

        my @all_results = map { $_->{result} } @pawn_logs;
        for my $r (@all_results) {
            ok $r eq 'sold' || $r eq 'seized', "pawn result valid: $r";
        }
    }
};

subtest 'Routine handles AP exhaustion in loops' => sub {
    my $agent = _make_agent;
    $agent->login('test-ap-exhaust');
    _ensure_season_and_char('test-ap-exhaust');

    my $char;
    $t->app->characters->load;
    ($char) = @{ $t->app->characters->find(sub { $_[0]->{name} eq 'test-ap-exhaust' }) };
    SKIP: {
        skip 'No character', 2 unless $char;

        $char->setCol('action_points', 0);
        $char->setCol('scrap', 100);
        $char->save;

        my $routine = MagicMountain::Bot::Routine->new(agent => $agent);
        my $profile = {
            id           => 'test_ap',
            push_policy  => { name => 'fixed_pushes', params => { max => 5 } },
            sell_policy  => { name => 'opportunist', params => {} },
            skill_policy => { name => 'never' },
        };

        my $result = $routine->run_day($profile);
        ok $result->{ok}, 'run_day ok with 0 AP';
        is $result->{actions}, 0, 'no actions with 0 AP';
    }
};

subtest 'Routine handles invalid profile' => sub {
    my $agent = _make_agent;
    my $routine = MagicMountain::Bot::Routine->new(agent => $agent);

    my $result = $routine->run_day;
    ok !$result->{ok}, 'run_day fails without profile';
    is $result->{error}, 'No bot profile', 'correct error message';
};

done_testing;
