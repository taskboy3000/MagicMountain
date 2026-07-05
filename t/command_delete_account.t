use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Season;
use MagicMountain::Model::Session;

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
my $shed  = MagicMountain::Model::ShedItem->new(file => "$data_dir/shed.json");
my $sess  = MagicMountain::Model::Session->new(file => "$data_dir/sessions.json");

MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
    ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

sub create_account {
    my ($name) = @_;
    my $a = $accts->create(username => $name);
    $a->save;
    $chars->create(
        name => $name, account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;
    return $a;
}

sub create_shed_item {
    my ($char_id) = @_;
    my $item = $shed->create(
        char_id => $char_id, artifact_id => 'test_item',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['test'],
        estimated_value_min => 8, estimated_value_max => 12,
    );
    $item->save;
    return $item;
}

sub session_count { scalar keys %{ $sess->all } }
sub account_count { scalar keys %{ $accts->all } }
sub char_count    { scalar keys %{ $chars->all } }
sub shed_count    { scalar keys %{ $shed->all } }

# ── Setup: create target accounts plus one non-matching account ──
my $keep     = create_account('keep_me');
my $delete_1 = create_account('smoke_test_001');
my $delete_2 = create_account('smoke_test_002');

# Add shed items to the delete targets (use character ids, not account ids)
$chars->load;
my ($char_1) = @{ $chars->find(sub { $_[0]->{account_id} eq $delete_1->getCol('id') }) };
my ($char_2) = @{ $chars->find(sub { $_[0]->{account_id} eq $delete_2->getCol('id') }) };
create_shed_item($char_1->getCol('id'));
create_shed_item($char_2->getCol('id'));
create_shed_item($char_1->getCol('id'));

# Add a session for one delete target
$sess->create(player_id => $delete_1->getCol('id'), last_active => time)->save;

is(account_count, 3, '3 accounts before deletion');
is(char_count,    3, '3 characters before deletion');
is(shed_count,    3, '3 shed items before deletion');
is(session_count, 1, '1 session before deletion');

# ── Test --name single delete ──
use MagicMountain;
my $app = MagicMountain->new;
$app->startup;
$app->commands->run('delete_account', '--name', 'smoke_test_001');

is(account_count, 2, '2 accounts after --name delete');
$shed->reload;
is(shed_count,    1, 'shed items for deleted account removed');
$sess->reload;
is(session_count, 0, 'session for deleted account removed');

# ── Test --prefix --force bulk delete ──
$app->commands->run('delete_account', '--prefix', 'smoke_test', '--force');

$accts->reload;
$chars->reload;
is(account_count, 1, '1 account after --prefix delete');
is(char_count,    1, 'only keep_me character remains');

# ── Verify the kept account still exists ──
$accts->reload;
ok($accts->find_by_username('keep_me'), 'non-matching account preserved');

done_testing;
