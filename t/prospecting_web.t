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

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, turns_remaining => 5,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

subtest 'unauthenticated' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/artifact/begin')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'begin — starts a new artifact' => sub {
    my $t = setup;
    $t->post_ok('/artifact/begin')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start')
      ->json_has('/artifact/id')
      ->json_is('/artifact/stage' => 'stable');
};

subtest 'begin while processing fails' => sub {
    my $t = setup;
    $t->post_ok('/artifact/begin')->status_is(200);
    $t->post_ok('/artifact/begin')->status_is(500);
};

subtest 'push — advances artifact' => sub {
    my $t = setup;
    $t->post_ok('/artifact/begin')->status_is(200);
    $t->post_ok('/artifact/push')
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'full lifecycle: begin → push → stop → sell' => sub {
    my $t = setup;
    srand(42);
    $t->post_ok('/artifact/begin')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'start');

    my $collapsed = 0;
    for (1 .. 3) {
        $t->post_ok('/artifact/push')->status_is(200);
        $collapsed = $t->tx->res->json->{result} ne 'push';
        last if $collapsed;
    }

    SKIP: {
        skip 'artifact collapsed during pushes', 3 if $collapsed;
        $t->post_ok('/artifact/stop')
          ->status_is(200)
          ->json_is('/ok' => 1)
          ->json_is('/result' => 'stop');

        my $offers = $t->tx->res->json->{pending_sale}{offers};
        ok(@$offers > 0, 'offers generated');

        $t->post_ok('/sale/' . $offers->[0]{faction_id})
          ->status_is(200)
          ->json_is('/ok' => 1)
          ->json_is('/result' => 'sold');
    }
};

done_testing;
