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

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $season_model = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json");
$season_model->create(
    id => 's1', label => 'Test', status => 'active', day => 1, length => 30,
    faction_climate => { banned_traits => ['restricted'] },
)->save;

my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
my $a = $accts->create(username => 'pawn-test');
$a->save;

my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
$chars->create(
    name => 'pawn-test', account_id => $a->getCol('id'), season_id => 's1',
    score => 0, scrap => 0, action_points => 0, action_points_max => 15,
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

# Create a pending pawn activity so the character has an active session
my $activities = MagicMountain::Model::Activity->new(file => "$dataDir/activities.json");
$activities->create(
    char_id => $char->getCol('id'),
    type    => 'pawn',
    phase   => 'idle',
)->save;

$activities->load;
my $act = $activities->find(sub { $_[0]->{char_id} eq $char->getCol('id') })->[0];
$char->setCol('pending_activity_id', $act->getCol('id'));
$char->setCol('current_view', 'pawn');
$char->save;

my $t = TestEnv->create_app;
$t->app->log->level('fatal');
$t->post_ok('/sessions', json => { displayName => 'pawn-test' })->status_is(200);
my $csrf = $t->tx->res->json->{csrf_token} // '';

# Broker panel shows exhausted state
$t->get_ok('/pawn?_format=fragment')
  ->status_is(200)
  ->content_like(qr/no more budget/);

# PAWN button is disabled (no data-action-url)
$t->get_ok('/shed?_format=fragment&view=pawn')
  ->status_is(200)
  ->content_like(qr/disabled/)
  ->content_like(qr/no budget/);

# Offer action still returns 409 (safety net)
$shed->load;
my $item = $shed->find(sub { 1 })->[0];
$t->post_ok('/pawn/offer' => {'X-CSRF-Token' => $csrf} => json => { shed_item_id => $item->getCol('id') })
  ->status_is(409)
  ->json_has('/error')
  ->json_like('/error', qr/AP exhausted/);

done_testing;
