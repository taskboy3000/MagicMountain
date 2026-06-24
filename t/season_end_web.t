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

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

my $seasons = MagicMountain::Model::Season->new(file => "$data_dir/seasons.json");
my $season_obj = $seasons->create(id => 's1', label => 'Test', status => 'active', day => 15, length => 30);
$season_obj->save;

my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
my $alice = $chars->create(
    name => 'alice', account_id => 'a1', season_id => 's1',
    score => 100, scrap => 50, action_points => 5, action_points_max => 15,
    standing => { syndicate => 3 }, faction_sales => { syndicate => 2 },
);
$alice->save;

my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
my $account = $accts->create(username => 'alice');
$account->save;
my $player_id = $account->getCol('id');

# Create a shed item tied to this character
my $shed = MagicMountain::Model::ShedItem->new(file => "$data_dir/shed.json");
$shed->create(
    char_id => $alice->getCol('id'), artifact_id => 'thermal_box_001',
    original_value => 20, decayed_value => 15,
    condition => 'settling', days_in_shed => 3, instability => 8,
    stage => 'strained', push_count => 3, has_evolved => 0,
    behaviors => ['thermal'], estimated_value_min => 12, estimated_value_max => 18,
)->save;

my $t = Test::Mojo->new('MagicMountain');
$t->post_ok('/sessions', json => { displayName => 'alice' })->status_is(200);
my $csrf = $t->tx->res->json->{csrf_token} // '';

# Web season/end route is commented out (CLI only for now).
# subtest 'end season via web' => sub {
#     $t->post_ok('/season/end' => {'X-CSRF-Token' => $csrf})
#       ->status_is(200)
#       ->json_is('/ok' => 1);
# 
#     my $app = $t->app;
#     $app->seasons->load;
#     my $season = $app->seasons->get('s1');
#     is($season->getCol('status'), 'archived', 'season status -> archived');
#     ok(!defined $season->getCol('faction_state'), 'faction_state cleared');
# 
#     $app->characters->load;
#     my $remaining = $app->characters->find(sub { $_[0]->{season_id} eq 's1' });
#     is(scalar @$remaining, 0, 'all season characters deleted');
# 
#     $app->shed->load;
#     is(scalar keys %{ $app->shed->table }, 0, 'shed emptied');
# 
#     $app->season_records->load;
#     my $records = $app->season_records->find(sub { $_[0]->{season_id} eq 's1' });
#     is(scalar @$records, 1, 'one season record created');
# };

done_testing;
