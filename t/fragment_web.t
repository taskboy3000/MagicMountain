use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Season;

sub setup {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $t = Test::Mojo->new('MagicMountain');

    # Use the app's model instances to avoid mtime cache collisions (Model.pm
    # keys its load cache by hashref memory address, which can collide when
    # local model instances go out of scope and Perl reuses the address).
    $t->app->characters->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $char_id = $t->app->characters->find(sub { 1 })->[0]->getCol('id');

    $t->app->shed->create(
        char_id => $char_id,
        artifact_id => 'test_artifact_001',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub setup_with_dominance {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    my $season = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30);
    $season->setCol('faction_state', {
        syndicate      => { influence => 50 },
        purifiers      => { influence => 30 },
        faculty        => { influence => 20 },
        libremount     => { influence => 10 },
        revelationists => { influence =>  5 },
    });
    $season->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->app->characters->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'player fragment returns status panel' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->get_ok('/player?_format=fragment')
      ->status_is(200)
      ->content_like(qr{OPERATOR})
      ->content_like(qr{player});
};

subtest 'player fragment returns 204 when no character' => sub {
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

# subtest 'season fragment returns season info' => sub {
#     my $t = setup;
#     $t->get_ok('/season?_format=fragment')
#       ->status_is(200)
#       ->content_like(qr{Test})
#       ->content_like(qr{DAY 1 OF 30});
# };

subtest 'crier fragment returns bulletin' => sub {
    my $t = setup;
    $t->get_ok('/crier?_format=fragment')
      ->status_is(200)
      ->content_like(qr{TOWN CRIER});
};

subtest 'idle fragment returns standby panel' => sub {
    my $t = setup;
    $t->get_ok('/idle?_format=fragment')
      ->status_is(200)
      ->content_like(qr{STANDBY})
      ->content_like(qr{nav bar});
};

subtest 'prospecting fragment returns 204 when idle' => sub {
    my $t = setup;
    $t->get_ok('/prospecting?_format=fragment')->status_is(204);
};

subtest 'market fragment returns 204 when idle' => sub {
    my $t = setup;
    $t->get_ok('/market?_format=fragment')->status_is(204);
};

subtest 'shed fragment returns ledger' => sub {
    my $t = setup;
    $t->get_ok('/shed?_format=fragment')
      ->status_is(200)
      ->content_like(qr{SALVAGE LEDGER})
      ->content_like(qr{test_artifact_001});
};

subtest 'shed fragment has no offer buttons when market idle' => sub {
    my $t = setup;
    $t->get_ok('/shed?_format=fragment')
      ->status_is(200)
      ->content_unlike(qr{offer-btn});
};

subtest 'shed fragment shows offer buttons when market active' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    $t->get_ok('/shed?_format=fragment')
      ->status_is(200)
      ->content_like(qr{offer-btn});
};

subtest 'skills fragment returns training records' => sub {
    my $t = setup;
    $t->get_ok('/skills?_format=fragment')
      ->status_is(200)
      ->content_like(qr{CERT STORE});
};

subtest 'factions fragment shows mountain dominance chart' => sub {
    my $t = setup_with_dominance;
    $t->get_ok('/factions?_format=fragment')
      ->status_is(200)
      ->content_like(qr{TERRAIN SCAN}, 'mountain chart header')
      ->content_like(qr{data-reference-id="faction_syndicate"}, 'syndicate reference link')
      ->content_like(qr{data-reference-id="faction_purifiers"}, 'purifiers reference link')
      ->content_like(qr{\x{2588}}, 'raster solid block present')
      ->content_like(qr{SYND.8TE}, 'short name present');
};

subtest 'leaderboard fragment returns rankings' => sub {
    my $t = setup;
    $t->get_ok('/leaderboard?_format=fragment')
      ->status_is(200)
      ->content_like(qr{RANKINGS});
};

done_testing;
