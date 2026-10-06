use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::Mojo;
use Test::More;
use File::Temp qw(tempdir);
use TestEnv;

use MagicMountain::Model::Season;
use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Activity;

my $t = TestEnv->create_app;
$t->app->log->level('fatal');

# Unauthenticated access redirects to login
$t->get_ok('/pawn')->status_is(302);

# A player must not be able to trade while another activity is in flight: the
# lazy create in _activity_action repoints pending_activity_id at a fresh pawn
# row and orphans the in-progress activity, losing whatever it was holding.
subtest 'POST /pawn/offer refuses while a prospecting expedition is active' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    local $ENV{MM_DATA_DIR} = $dataDir;

    my $season_model = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json");
    $season_model->create(
        id => 's1', label => 'Test', status => 'active', day => 1, length => 30,
        faction_climate => { banned_traits => ['restricted'] },
    )->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    $accts->create(username => 'orphan-test')->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'orphan-test',
        account_id => $accts->find(sub { 1 })->[0]->getCol('id'),
        season_id => 's1',
        score => 0, scrap => 0, action_points => 5, action_points_max => 15,
        current_view => 'pawn',
    )->save;
    $chars->load;
    my $char = $chars->find(sub { 1 })->[0];

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char->getCol('id'), artifact_id => 'test_restricted',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['restricted'],
        estimated_value_min => 15, estimated_value_max => 25,
    )->save;

    my $activities = MagicMountain::Model::Activity->new(file => "$dataDir/activities.json");
    $activities->create(
        char_id => $char->getCol('id'),
        type    => 'prospecting',
        phase   => 'processing',
    )->save;
    $activities->load;
    my $prosp    = $activities->find(sub { $_[0]->{type} eq 'prospecting' })->[0];
    my $prosp_id = $prosp->getCol('id');

    $char->setCol('pending_activity_id', $prosp_id);
    $char->save;

    my $t2 = TestEnv->create_app;
    $t2->app->log->level('fatal');
    $t2->post_ok('/sessions', json => { displayName => 'orphan-test' })->status_is(200);
    my $csrf = $t2->tx->res->json->{csrf_token} // '';

    my $item = $shed->find(sub { 1 })->[0];
    $t2->post_ok('/pawn/offer' => {'X-CSRF-Token' => $csrf} => json => {
        shed_item_id => $item->getCol('id'),
    })->status_is(400)->json_is('/ok' => 0);

    $chars->load;
    is($chars->get($char->getCol('id'))->getCol('pending_activity_id'), $prosp_id,
       'pending_activity_id still points at the expedition');

    $activities->load;
    my $still = $activities->get($prosp_id);
    ok($still, 'the prospecting activity row still exists');
    is($still->getCol('phase'), 'processing', 'and is still mid-processing');
    is(scalar @{ $activities->find(sub { $_[0]->{type} eq 'pawn' }) }, 0,
       'no pawn activity row was created');

    $shed->load;
    ok($shed->get($item->getCol('id')), 'the artifact was not sold');

    $chars->load;
    is($chars->get($char->getCol('id'))->getCol('action_points'), 5,
       'no AP was consumed');
};

done_testing;
