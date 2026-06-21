use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;

sub setup {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    write_file("$dataDir/accounts.json",    '{}');
    write_file("$dataDir/characters.json",  '{}');
    write_file("$dataDir/sessions.json",    '{}');
    write_file("$dataDir/activities.json",  '{}');
    write_file("$dataDir/seasons.json",     '{"s1": {"id":"s1","label":"Test","status":"active","day":1,"length":30}}');

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

subtest 'unauthenticated' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/prospecting/begin')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'begin — starts a new artifact' => sub {
    my $t = setup;
    $t->post_ok('/prospecting/begin')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start')
      ->json_has('/artifact/id')
      ->json_is('/artifact/stage' => 'stable');
};

subtest 'begin while processing fails' => sub {
    my $t = setup;
    $t->post_ok('/prospecting/begin')->status_is(200);
    $t->post_ok('/prospecting/begin')->status_is(500);
};

subtest 'push — advances artifact' => sub {
    my $t = setup;
    $t->post_ok('/prospecting/begin')->status_is(200);
    $t->post_ok('/prospecting/push')
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'begin picks active-season character over orphaned character' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    write_file("$dataDir/accounts.json",   '{}');
    write_file("$dataDir/characters.json", '{}');
    write_file("$dataDir/sessions.json",   '{}');
    write_file("$dataDir/activities.json", '{}');
    write_file("$dataDir/seasons.json",    '{"s0":{"id":"s0","label":"Old","status":"archived","day":30},"s1":{"id":"s1","label":"Current","status":"active","day":1,"length":30}}');

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(name => 'player', account_id => $a->getCol('id'),
        season_id => 's0', score => 0, scrap => 99, action_points => 15, action_points_max => 15)->save;
    $chars->create(name => 'player', account_id => $a->getCol('id'),
        season_id => 's1', score => 0, scrap => 0,  action_points => 15, action_points_max => 15)->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    $t->post_ok('/prospecting/begin')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/scrap' => 0, 'used active-season character (scrap=0, not orphan scrap=99)');
};

subtest 'full lifecycle: begin → push → stop' => sub {
    my $t = setup;
    srand(42);
    $t->post_ok('/prospecting/begin')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start');

    my $collapsed = 0;
    for (1 .. 3) {
        $t->post_ok('/prospecting/push')->status_is(200);
        $collapsed = $t->tx->res->json->{result} ne 'push';
        last if $collapsed;
    }

    SKIP: {
        skip 'artifact collapsed during pushes', 1 if $collapsed;
        $t->post_ok('/prospecting/stop')
          ->status_is(200)
          ->json_is('/ok' => 1)
          ->json_is('/result' => 'stopped');
    }
};

done_testing;
