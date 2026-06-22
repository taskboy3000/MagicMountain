use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Season;

subtest 'season with zero characters' => sub {
    my $data_dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $data_dir;
    $ENV{MM_SKIP_SEASON_CHECK} = 1;
    MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 15, length => 30)->save;

    use MagicMountain;
    my $app = MagicMountain->new;
    $app->startup;
    $app->commands->run('end_season');
    $app->seasons->load;
    is($app->seasons->get('s1')->getCol('status'), 'archived', 'empty season archived');
};

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
    ->create(id => 's1', label => 'Test', status => 'active', day => 15, length => 30)->save;

use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::ArtifactDisposition;

my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
my $alice = $chars->create(name => 'alice', account_id => 'a1', season_id => 's1',
    score => 100, scrap => 50, action_points => 5, action_points_max => 15,
    skill_prospecting => 2, skill_upcycling => 1, skill_selling => 0,
    standing => { syndicate => 3, faculty => 1 },
    faction_sales => { syndicate => 2, faculty => 1 },
);
$alice->save;

my $bob = $chars->create(name => 'bob', account_id => 'a2', season_id => 's1',
    score => 200, scrap => 30, action_points => 10, action_points_max => 15,
    skill_prospecting => 1, skill_upcycling => 0, skill_selling => 2,
    standing => { syndicate => 5 },
    faction_sales => { syndicate => 3 },
);
$bob->save;

my $shed = MagicMountain::Model::ShedItem->new(file => "$data_dir/shed.json");
$shed->create(
    char_id => $alice->getCol('id'),
    artifact_id => 'thermal_box_001', original_value => 20, decayed_value => 15,
    condition => 'settling', days_in_shed => 3, instability => 8, stage => 'strained',
    push_count => 3, has_evolved => 0, behaviors => ['thermal'],
    estimated_value_min => 12, estimated_value_max => 18,
)->save;

my $disc = MagicMountain::Model::ArtifactDisposition->new(file => "$data_dir/dispositions.json");
$disc->create(
    season_id => 's1', player_id => $alice->getCol('account_id'),
    faction_id => 'syndicate', season_day => 10, value_awarded => 60,
    artifact_snapshot => { artifact_id => 'void_core_001', has_evolved => 1 },
    standing_delta => 2, influence_delta => 60, narrative_hooks => {},
)->save;

use MagicMountain;
my $app = MagicMountain->new;
$app->startup;

$app->commands->run('end_season');

# Verify season is archived
$app->seasons->load;
my $season = $app->seasons->get('s1');
is($season->getCol('status'), 'archived', 'season status -> archived');
ok(!defined $season->getCol('faction_state'), 'faction_state cleared');

# Verify characters deleted
$app->characters->load;
my $remaining = $app->characters->find(sub { $_[0]->{season_id} eq 's1' });
is(scalar @$remaining, 0, 'all season characters deleted');

# Verify shed empty
$app->shed->load;
is(scalar keys %{ $app->shed->table }, 0, 'shed emptied');

# Verify SeasonRecords created
$app->season_records->load;
my $records = $app->season_records->find(sub { $_[0]->{season_id} eq 's1' });
is(scalar @$records, 2, 'two season records created');

my ($alice_rec) = grep { $_->getCol('final_score') == 100 } @$records;
my ($bob_rec)   = grep { $_->getCol('final_score') == 200 } @$records;
ok($alice_rec, 'alice record found');
ok($bob_rec, 'bob record found');

is($bob_rec->getCol('rank'), 1, 'bob ranked 1 (score 200)');
is($alice_rec->getCol('rank'), 2, 'alice ranked 2 (score 100)');
is($alice_rec->getCol('final_scrap'), 50, 'alice scrap preserved');
is($alice_rec->getCol('skills_snapshot')->{prospecting}, 2, 'alice skill preserved');
is($alice_rec->getCol('faction_standing_snapshot')->{syndicate}, 3, 'alice standing preserved');

my $hl = $alice_rec->getCol('story_highlights');
is($hl->{total_sales}, 1, 'highlights: 1 sale');
is($hl->{top_sale_value}, 60, 'highlights: top value 60');
is($hl->{evolved_artifacts_sold}, 1, 'highlights: 1 evolved');

done_testing;
