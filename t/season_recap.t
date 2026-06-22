use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;
use MagicMountain::Model::SeasonRecord;

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;

# Pre-seed: archived season + season record for player
MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
    ->create(id => 's1', label => 'Season 1', status => 'archived', day => 30, length => 30)->save;

# Create a player account
my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
my $a = $accts->create(username => 'alice');
$a->save;
my $player_id = $a->getCol('id');

# Create a SeasonRecord for the archived season
my $recs = MagicMountain::Model::SeasonRecord->new(file => "$data_dir/season_records.json");
$recs->create(
    season_id   => 's1',
    player_id   => $player_id,
    final_score => 150,
    final_scrap => 75,
    rank        => 2,
    faction_standing_snapshot => { syndicate => 4, faculty => 1 },
    skills_snapshot          => { prospecting => 2, upcycling => 1, selling => 0 },
    story_highlights         => {
        total_sales         => 3,
        top_sale_value      => 60,
        top_sale_faction    => 'syndicate',
        factions_sold_to    => ['faculty', 'syndicate'],
        evolved_artifacts_sold => 1,
    },
)->save;

use MagicMountain;
my $t = Test::Mojo->new('MagicMountain');

# Login
$t->post_ok('/sessions', json => { displayName => 'alice' })->status_is(200);

# Visit /game — should show recap + auto-create new season
$t->get_ok('/game' => {Accept => 'application/json'})
  ->status_is(200)
  ->json_is('/ok' => 1);

# Verify season_recap is present
$t->json_has('/season_recap', 'season_recap is present');
$t->json_is('/season_recap/label' => 'Season 1', 'recap label correct');
$t->json_is('/season_recap/final_score' => 150, 'recap score correct');
$t->json_is('/season_recap/rank' => 2, 'recap rank correct');
$t->json_has('/season_recap/highlights', 'recap has highlights');

# Verify a new active season was auto-created
$t->json_has('/season', 'season is present');
$t->json_is('/season/day' => 1, 'new season starts at day 1');
$t->json_is('/season/total_days' => 30, 'new season default length');

# Verify a fresh character was created for the new season
$t->json_has('/player', 'player is present');
$t->json_is('/player/name' => 'alice', 'player name from account');
$t->json_is('/player/score' => 0, 'fresh character score 0');
$t->json_is('/player/scrap' => 0, 'fresh character scrap 0');
$t->json_is('/player/action_points' => 15, 'fresh character full AP');

# Second visit — recap should NOT appear again
$t->get_ok('/game' => {Accept => 'application/json'})
  ->status_is(200)
  ->json_hasnt('/season_recap', 'recap gone on second visit');

done_testing;
