use Modern::Perl;
use Test::More;

if ($ENV{GITHUB_ACTIONS}) {
    plan skip_all => 'skipping web integration test in GitHub CI';
}
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
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
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'unauthenticated' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/prospecting/begin')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'begin — starts a new artifact' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start')
      ->json_has('/artifact/id');
    my $stage = $t->tx->res->json->{artifact}{stage};
    ok($stage eq 'stable' || $stage eq 'strained', "artifact stage is $stage");
};

subtest 'begin while processing fails' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})
      ->status_is(409)
      ->json_is('/ok' => 0);
};

subtest 'push — advances artifact' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    $t->post_ok('/prospecting/push' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'begin picks active-season character over orphaned character' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    my $seasons = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json");
    $seasons->create(id => 's0', label => 'Old', status => 'archived', day => 30, length => 30)->save;
    $seasons->create(id => 's1', label => 'Current', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(name => 'player', account_id => $a->getCol('id'),
        season_id => 's0', score => 0, scrap => 99, action_points => 15, action_points_max => 15)->save;
    $chars->create(name => 'player', account_id => $a->getCol('id'),
        season_id => 's1', score => 0, scrap => 0,  action_points => 15, action_points_max => 15)->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/scrap' => 0, 'used active-season character (scrap=0, not orphan scrap=99)');
};

subtest 'fragment renders artifact icon, value_label, and buttons' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $t->get_ok('/prospecting?_format=fragment')
      ->status_is(200)
      ->content_like(qr{src="/images/artifact_\w+\.svg"}, 'artifact icon URL')
      ->content_like(qr{VALUE: <strong>(negligible|low|middling|ordinary|uncommon|rare|high)</strong>}, 'value_label in HTML')
      ->content_like(qr{id="btn-push"}, 'push button present')
      ->content_like(qr{id="btn-stop"}, 'stop button present');
};

subtest 'full lifecycle: begin → push → stop' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    srand(42);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start');

    my $collapsed = 0;
    for (1 .. 3) {
        $t->post_ok('/prospecting/push' => {'X-CSRF-Token' => $csrf})->status_is(200);
        $collapsed = $t->tx->res->json->{result} ne 'push';
        last if $collapsed;
    }

    SKIP: {
        skip 'artifact collapsed during pushes', 1 if $collapsed;
        $t->post_ok('/prospecting/stop' => {'X-CSRF-Token' => $csrf})
          ->status_is(200)
          ->json_is('/ok' => 1)
          ->json_is('/result' => 'stopped');
    }
};

done_testing;
