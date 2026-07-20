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

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
    ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
my $a = $accts->create(username => 'player');
$a->save;

my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
$chars->create(name => 'alice', account_id => $a->getCol('id'), season_id => 's1',
    score => 30, scrap => 5,  action_points => 15, action_points_max => 15)->save;
$chars->create(name => 'bob',   account_id => $a->getCol('id'), season_id => 's1',
    score => 50, scrap => 10, action_points => 15, action_points_max => 15)->save;
$chars->create(name => 'carol', account_id => $a->getCol('id'), season_id => 's1',
    score => 20, scrap => 0,  action_points => 15, action_points_max => 15)->save;

my $t = Test::Mojo->new('MagicMountain');
$t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
$t->get_ok('/leaderboard')
  ->status_is(200)
  ->json_is('/ok' => 1)
  ->json_has('/leaderboard')
  ->json_is('/leaderboard/0/rank'  => 1)->json_is('/leaderboard/0/name'  => 'bob')  ->json_is('/leaderboard/0/score' => 50)->json_is('/leaderboard/0/bot' => 0)->json_is('/leaderboard/0/badge' => undef)
  ->json_is('/leaderboard/1/rank'  => 2)->json_is('/leaderboard/1/name'  => 'alice')->json_is('/leaderboard/1/score' => 30)->json_is('/leaderboard/1/bot' => 0)->json_is('/leaderboard/1/badge' => undef)
  ->json_is('/leaderboard/2/rank'  => 3)->json_is('/leaderboard/2/name'  => 'carol')  ->json_is('/leaderboard/2/score' => 20)->json_is('/leaderboard/2/bot' => 0)->json_is('/leaderboard/2/badge' => undef);

done_testing;;
