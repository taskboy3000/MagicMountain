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
        total_sales            => 3,
        top_sale_value         => 60,
        top_sale_faction       => 'syndicate',
        factions_sold_to       => ['faculty', 'syndicate'],
        evolved_artifacts_sold => 1,
        top_faction            => 'syndicate',
        top_faction_influence  => 150,
        factions_competing     => 3,
    },
)->save;

my $t = TestEnv->create_app;

subtest 'unauthenticated redirects to login' => sub {
    my $t2 = TestEnv->create_app;
    $t2->get_ok('/season/recap?_format=fragment')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'login and game recap on first visit' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice' })->status_is(200);

    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->json_has('/season_recap', 'season_recap is present');
    $t->json_is('/season_recap/label' => 'Season 1', 'recap label correct');
    $t->json_is('/season_recap/final_score' => 150, 'recap score correct');
    $t->json_is('/season_recap/rank' => 2, 'recap rank correct');
    $t->json_has('/season_recap/highlights', 'recap has highlights');

    $t->json_has('/season', 'season is present');
    $t->json_is('/season/day' => 1, 'new season starts at day 1');
    $t->json_is('/season/total_days' => 30, 'new season default length');

    $t->json_has('/player', 'player is present');
    $t->json_is('/player/name' => 'alice', 'player name from account');
    $t->json_is('/player/score' => 0, 'fresh character score 0');
    $t->json_is('/player/scrap' => 0, 'fresh character scrap 0');
    $t->json_is('/player/action_points' => 20, 'fresh character full AP');
};

subtest 'second visit — recap gone' => sub {
    $t->get_ok('/game' => {Accept => 'application/json'})
      ->status_is(200)
      ->json_hasnt('/season_recap', 'recap gone on second visit');
};

subtest '/season/recap fragment returns narrative sections' => sub {
    $t->get_ok('/season/recap?_format=fragment');
    $t->status_is(200);
    $t->content_like(qr/COMPANY CONFIDENTIAL/);
    $t->content_like(qr/PROSPECTBOY 3000/);
    $t->content_like(qr/MARKET HEALTH OVERVIEW/);
    $t->content_like(qr/AGENT IMPACT ANALYSIS/);
    $t->content_like(qr/PERSONAL ACCOMPLISHMENTS/);
    $t->content_like(qr/CENTRAL ARCHIVE/);
    $t->content_like(qr/>150</);
    $t->content_like(qr/>75</);
    $t->content_like(qr/>2</);
    $t->content_like(qr/The Syndicate/);
    $t->content_like(qr/The Faculty/);
};

subtest '/season/recap with specific season_id' => sub {
    $t->get_ok('/season/recap?season_id=s1&_format=fragment')
      ->status_is(200)
      ->content_like(qr/Season 1/);
};

subtest '/season/recap JSON endpoint' => sub {
    $t->get_ok('/season/recap')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/sections')
      ->json_is('/final_score' => 150)
      ->json_has('/highlights');
};

subtest 'no archived seasons returns 204' => sub {
    # Fresh data dir with no seasons at all
    my $clean_dir = tempdir(CLEANUP => 1);
    local $ENV{MM_DATA_DIR} = $clean_dir;

    my $accts = MagicMountain::Model::Account->new(file => "$clean_dir/accounts.json");
    my $a = $accts->create(username => 'lonely');
    $a->save;

    my $t2 = TestEnv->create_app;
    $t2->post_ok('/sessions', json => { displayName => 'lonely' })->status_is(200);
    $t2->get_ok('/season/recap')
      ->status_is(204);
};

subtest 'specific season_id with no player record returns 204' => sub {
    my $clean_dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $clean_dir;

    # Create archived season
    MagicMountain::Model::Season->new(file => "$clean_dir/seasons.json")
        ->create(id => 's_other', label => 'Other', status => 'archived', day => 1, length => 30)->save;

    # Player with no record
    my $accts = MagicMountain::Model::Account->new(file => "$clean_dir/accounts.json");
    my $a = $accts->create(username => 'norecord');
    $a->save;

    my $t2 = TestEnv->create_app;
    $t2->post_ok('/sessions', json => { displayName => 'norecord' })->status_is(200);
    $t2->get_ok('/season/recap?season_id=s_other')
      ->status_is(204);
};

subtest 'season archive on account tab' => sub {
    $t->get_ok('/account?_format=fragment')
      ->status_is(200)
      ->content_like(qr/SEASON ARCHIVE/)
      ->content_like(qr/Season 1/)
      ->content_like(qr/Complete/)
      ->content_like(qr/150/);
};

done_testing;
