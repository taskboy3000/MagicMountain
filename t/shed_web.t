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

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
        skill_prospecting => 1,
    )->save;

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
    $shed->create(
        char_id => $char_id, artifact_id => 'crystal_001',
        original_value => 30, decayed_value => 25,
        condition => 'fading', days_in_shed => 7,
        instability => 5, stage => 'unstable', push_count => 4,
        has_evolved => 1, behaviors => ['signal', 'field'],
        estimated_value_min => 20, estimated_value_max => 30,
    )->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

subtest 'unauthenticated redirects' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->get_ok('/shed')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'JSON returns shed items' => sub {
    my $t = setup;
    $t->get_ok('/shed' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/total' => 2)
      ->json_is('/count' => 2)
      ->json_has('/shed/0/id')
      ->json_has('/shed/1/id');
};

subtest 'has_evolved flag is 0 or 1' => sub {
    my $t = setup;
    $t->get_ok('/shed' => {Accept => 'application/json'})
      ->status_is(200);
    my $items = $t->tx->res->json->{shed};
    my %by_id = map { $_->{artifact_id} => $_ } @$items;
    is($by_id{thermal_box_001}{has_evolved}, 0, 'non-evolved item has 0');
    is($by_id{crystal_001}{has_evolved},     1, 'evolved item has 1');
};



subtest 'sort by artifact_id asc' => sub {
    my $t = setup;
    $t->get_ok('/shed' => {Accept => 'application/json'})
      ->status_is(200);
};

subtest 'filter by condition' => sub {
    my $t = setup;
    $t->get_ok('/shed' => {Accept => 'application/json'})
      ->status_is(200);
};

subtest 'climate premium badge in shed fragment' => sub {
    my $t = setup;

    # Give one shed item a climate-matching behavior
    my $shed = MagicMountain::Model::ShedItem->new(file => "$ENV{MM_DATA_DIR}/shed.json");
    $shed->load;
    my $it = $shed->find(sub { 1 })->[0];
    $it->setCol('behaviors', ['volatile']);
    $it->save;

    # Set climate with buyer_trait_biases
    my $season = MagicMountain::Model::Season->new(file => "$ENV{MM_DATA_DIR}/seasons.json");
    $season->load;
    my $s = $season->find(sub { 1 })->[0];
    $s->setCol('faction_climate', {
        dominant_faction_name => 'The Syndicate',
        intensity_label => 'Intense',
        intensity => 2,
        market => {
            buyer_trait_biases => { volatile => 1, luxury => 1 },
            market_summary => 'Rich buyers',
        },
        town_crier => { hint => 'test' },
    });
    $s->save;

    $t->get_ok('/shed?_format=fragment')->status_is(200);
    my $html = $t->tx->res->body;
    like($html, qr/mm-text-amber/, 'climate premium badge class present');
    like($html, qr/title="premium"/, 'premium badge title present');
};

subtest 'shed fragment — tags gated when skill_prospecting=0' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'rookie'); $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'rookie', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
        skill_prospecting => 0,
    )->save;

    my $char = $chars->find(sub { 1 })->[0];
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char->getCol('id'), artifact_id => 'thermal_box_001',
        original_value => 20, decayed_value => 18, condition => 'fresh',
        days_in_shed => 1, instability => 3, stage => 'strained', push_count => 2,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 14, estimated_value_max => 22,
    )->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'rookie' })->status_is(200);
    $t->get_ok('/shed?_format=fragment')->status_is(200);
    my $html = $t->tx->res->body;
    like($html, qr/\b-\b/, 'gated shed tags show dash placeholder');
    unlike($html, qr/mm-text-amber/, 'no amber tag spans when gated in shed');
};

done_testing;
