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

sub setup_with_char {
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

    my $char_id = $chars->find(sub { 1 })->[0]->getCol('id');
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id, artifact_id => 'test_cog',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 8, estimated_value_max => 12,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'prospecting show returns JSON without _format' => sub {
    my $t = setup_with_char;
    my $csrf = _csrf($t);

    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $t->get_ok('/prospecting')
      ->status_is(200)
      ->json_has('/prospecting')
      ->json_has('/prospecting/id')
      ->json_has('/prospecting/stage')
      ->json_has('/prospecting/value_tier');
};

subtest 'market show returns JSON without _format' => sub {
    my $t = setup_with_char;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $t->get_ok('/market')
      ->status_is(200)
      ->json_has('/market_visit')
      ->json_has('/market_visit/faction_id')
      ->json_has('/market_visit/irritation');
};

subtest '_require_character returns 404 for endpoints without character' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'lonely');
    $a->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'lonely' })->status_is(200);

    $t->get_ok('/idle?_format=fragment')
      ->status_is(404)
      ->json_is('/error', 'No character');
};

subtest 'idle show returns JSON without _format' => sub {
    my $t = setup_with_char;
    $t->get_ok('/idle')
      ->status_is(200)
      ->json_has('/can_prospect')
      ->json_has('/can_market');
};

subtest 'factions show returns JSON without _format' => sub {
    my $t = setup_with_char;
    $t->get_ok('/factions')
      ->status_is(200)
      ->json_has('/factions')
      ->json_has('/standing')
      ->json_has('/faction_sales');
};

subtest 'skills index returns JSON without _format' => sub {
    my $t = setup_with_char;
    $t->get_ok('/skills')
      ->status_is(200)
      ->json_has('/skills');
};

subtest 'prospecting show includes _self.actions' => sub {
    my $t = setup_with_char;
    my $csrf = _csrf($t);
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    $t->get_ok('/prospecting')
      ->status_is(200)
      ->json_has('/_self')
      ->json_has('/_self/actions')
      ->json_has('/_self/actions/0/attrs')
      ->json_has('/_self/actions/0/label');
};

subtest 'market show includes _self.actions' => sub {
    my $t = setup_with_char;
    my $csrf = _csrf($t);
    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    $t->get_ok('/market')
      ->status_is(200)
      ->json_has('/_self')
      ->json_has('/_self/actions')
      ->json_has('/_self/actions/0/attrs')
      ->json_has('/_self/actions/0/label');
};

subtest 'idle show includes _self.actions' => sub {
    my $t = setup_with_char;
    $t->get_ok('/idle')
      ->status_is(200)
      ->json_has('/_self')
      ->json_has('/_self/actions');
};

subtest 'account show includes _self.actions' => sub {
    my $t = setup_with_char;
    $t->get_ok('/account')
      ->status_is(200)
      ->json_has('/_self')
      ->json_has('/_self/actions');
};

subtest 'nav tabs include action_url on prospect tab' => sub {
    my $t = setup_with_char;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_has('/primary_tabs')
      ->json_has('/primary_tabs/1/action_url')
      ->json_hasnt('/primary_tabs/0/action_url');
};

done_testing;
