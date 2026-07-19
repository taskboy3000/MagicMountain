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
        score => 0, scrap => 2000, action_points => 15, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'unauthenticated redirects' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->get_ok('/skills')
      ->status_is(302)
      ->header_like(Location => qr{/login});
    $t->post_ok('/skills/purchase')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'index — lists skills with current levels' => sub {
    my $t = setup;
    $t->get_ok('/skills')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/skills')
      ->json_is('/skills/0/id' => 'prospecting')
      ->json_is('/skills/0/current_level' => 0)
      ->json_is('/skills/1/id' => 'upcycling')
      ->json_is('/skills/1/current_level' => 0)
      ->json_is('/skills/2/id' => 'selling')
      ->json_is('/skills/2/current_level' => 0);
};

subtest 'purchase — missing skill_id dies' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => {})
      ->status_is(400);
};

subtest 'purchase — unknown skill_id dies' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'nonexistent' });
    if ($t->tx->res->code != 400) {
        diag "body: " . $t->tx->res->body;
    }
    $t->status_is(400);
};

subtest 'purchase — insufficient scrap dies' => sub {
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

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    my $csrf = _csrf($t);
    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(400);
};

subtest 'purchase — already at max dies' => sub {
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
        score => 0, scrap => 999, action_points => 15, action_points_max => 15,
        skill_prospecting => 4,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    my $csrf = _csrf($t);
    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(400);
};

subtest 'index — max-level skill has no upgrade action' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'master');
    $a->save;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'master', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 9999, action_points => 15, action_points_max => 15,
        skill_prospecting => 4,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'master' })->status_is(200);
    $t->get_ok('/skills')
      ->status_is(200)
      ->json_is('/ok' => 1);

    my $json = $t->tx->res->json;
    my ($prospecting) = grep { $_->{id} eq 'prospecting' } @{ $json->{skills} };
    ok $prospecting, 'prospecting skill present';
    is $prospecting->{current_level}, 4, 'at max level';

    # Verify no purchase action in _self for max-level skill
    my @prospecting_actions = grep {
        $_->{attrs}{'data-skill-id'} && $_->{attrs}{'data-skill-id'} eq 'prospecting'
    } @{ $json->{_self}{actions} // [] };
    is scalar @prospecting_actions, 0, 'no upgrade action for maxed skill';

    # Other skills should still have actions
    my @other_actions = grep {
        $_->{attrs}{'data-skill-id'} && $_->{attrs}{'data-skill-id'} ne 'prospecting'
    } @{ $json->{_self}{actions} // [] };
    ok scalar @other_actions > 0, 'other skills still show upgrade actions';
};

subtest 'purchase — success deducts scrap and increases level' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player'); $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 2000, action_points => 15, action_points_max => 15,
    )->save;
    my $char = $chars->find(sub { 1 })->[0];
    my $prev_scrap = $char->getCol('scrap');

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    my $csrf = _csrf($t);

    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/score' => 0);
    my $scrap1 = $t->tx->res->json->{player}{scrap};
    ok $scrap1 < $prev_scrap, 'scrap decreased after level 1 purchase';

    $t->get_ok('/skills')
      ->status_is(200)
      ->json_is('/skills/0/id' => 'prospecting')
      ->json_is('/skills/0/current_level' => 1);

    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(200)
      ->json_is('/ok' => 1);
    my $scrap2 = $t->tx->res->json->{player}{scrap};
    ok $scrap2 < $scrap1, 'scrap decreased after level 2 purchase';

    $t->get_ok('/skills')
      ->json_is('/skills/0/current_level' => 2);

    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(200)
      ->json_is('/ok' => 1);
    my $scrap3 = $t->tx->res->json->{player}{scrap};
    ok $scrap3 < $scrap2, 'scrap decreased after level 3 purchase';

    $t->get_ok('/skills')
      ->json_is('/skills/0/current_level' => 3);

    $t->post_ok('/skills/purchase' => {'X-CSRF-Token' => $csrf} => json => { skill_id => 'prospecting' })
      ->status_is(200)
      ->json_is('/ok' => 1);
    my $scrap4 = $t->tx->res->json->{player}{scrap};
    ok $scrap4 < $scrap3, 'scrap decreased after level 4 purchase';

    $t->get_ok('/skills')
      ->json_is('/skills/0/current_level' => 4);
};

done_testing;
