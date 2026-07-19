use Modern::Perl;
use Test::More;

if ($ENV{GITHUB_ACTIONS}) {
    plan skip_all => 'skipping web integration test in GitHub CI';
}
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

sub setup {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 42, scrap => 100, action_points => 15, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'show — unauthenticated returns 401 with JSON accept' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->get_ok('/player' => {Accept => 'application/json'})->status_is(401);
};

subtest 'show — JSON returns player info' => sub {
    my $t = setup;
    $t->get_ok('/player')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/displayName' => 'player')
      ->json_has('/player/id');
};

subtest 'show — fragment returns player name' => sub {
    my $t = setup;
    $t->get_ok('/player?_format=fragment')
      ->status_is(200)
      ->content_like(qr{player}, 'fragment has player name');
};

subtest 'show — fragment returns 204 when no character' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'lonely');
    $a->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'lonely' })->status_is(200);
    $t->get_ok('/player?_format=fragment')->status_is(204);
};

subtest 'destroy — deletes account and characters' => sub {
    my $t = setup;

    my $player_id = $t->tx->res->json->{player}{id};
    my $csrf = _csrf($t);

    $t->delete_ok('/player' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->app->accounts->load;
    ok !$t->app->accounts->get($player_id), 'account deleted';

    $t->app->characters->load;
    my @chars = @{ $t->app->characters->find(sub { $_[0]->{account_id} eq $player_id }) };
    is scalar @chars, 0, 'all characters deleted';
};

subtest 'destroy — unauthenticated returns 401 with JSON accept' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    my $t = Test::Mojo->new('MagicMountain');
    $t->delete_ok('/player' => {Accept => 'application/json'})->status_is(401);
};

subtest 'destroy — session cleared after account deletion' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->delete_ok('/player' => {'X-CSRF-Token' => $csrf})
      ->status_is(200);

    $t->get_ok('/player' => {Accept => 'application/json'})->status_is(401);
};

done_testing;
