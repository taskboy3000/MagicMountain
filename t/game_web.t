use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Season;

sub setup {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 5, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 42, scrap => 10, action_points => 15, action_points_max => 15,
    )->save;

    return $dataDir;
}

subtest 'JSON — returns full game state' => sub {
    my $dataDir = setup;
    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/player')
      ->json_is('/player/name' => 'player')
      ->json_is('/player/score' => 42)
      ->json_is('/player/scrap' => 10)
      ->json_is('/player/action_points' => 15)
      ->json_is('/season/day' => 5)
      ->json_is('/season/total_days' => 30)
      ->json_has('/world_message')
      ->json_has('/factions')
      ->json_is('/prospecting' => undef)
      ->json_is('/market_visit' => undef)
      ->json_has('/shed');

    $t->json_has('/player/skills')
      ->json_is('/player/skills/prospecting' => 0)
      ->json_is('/player/skills/upcycling' => 0)
      ->json_is('/player/skills/selling' => 0);
};

subtest 'JSON — shows shed items' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id, artifact_id => 'thermal_box_001',
        original_value => 20, decayed_value => 18,
        condition => 'fresh', days_in_shed => 1,
        instability => 3, stage => 'strained', push_count => 2,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 14, estimated_value_max => 22,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/shed/0/artifact_id' => 'thermal_box_001')
      ->json_is('/shed/0/condition' => 'fresh');
};

subtest 'JSON — shows prospecting resume when activity active' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    my $act = $t->app->prospecting->create(
        char_id => $char_id, phase => 'processing',
        artifact => { id => 'crystal_001', stage => 'strained', value => 30, signal => 'It hums.', intro => 'A faint glow.' },
    );
    $act->save;
    $char->setCol('pending_activity_id', $act->getCol('id'));
    $char->save;

    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/prospecting/id' => 'crystal_001')
      ->json_is('/prospecting/stage' => 'strained');
};

subtest 'JSON — shows market resume when activity active' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    my $act = $t->app->market->create(
        char_id => $char_id, phase => 'negotiating',
        customer => {
            faction_id => 'syndicate', faction_name => 'The Syndicate',
            disposition => 'commercial_resale', irritation => 2,
            desired_behaviors => ['thermal'], base_multiplier => 1.1,
            irritation_threshold => 5, settle_chance => 0.15,
        },
    );
    $act->save;
    $char->setCol('pending_activity_id', $act->getCol('id'));
    $char->save;

    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/market_visit/customer/faction_id' => 'syndicate')
      ->json_is('/market_visit/irritation' => 2);
};

subtest 'JSON — idle activity phase is not shown' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    my $act = $t->app->prospecting->create(char_id => $char_id, phase => 'idle');
    $act->save;
    $char->setCol('pending_activity_id', $act->getCol('id'));
    $char->save;

    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/prospecting' => undef);
};

subtest 'HTML — renders successfully' => sub {
    my $dataDir = setup;
    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/Magic Mountain/)
      ->content_like(qr/player/);
};

subtest 'JSON — displays faction_sales' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    $char->setCol('faction_sales', { syndicate => 3, faculty => 1 });
    $char->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/player/faction_sales/syndicate' => 3)
      ->json_is('/player/faction_sales/faculty' => 1);
};

done_testing;
