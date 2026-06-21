use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

write_file("$data_dir/accounts.json",   '{}');
write_file("$data_dir/characters.json", '{}');
write_file("$data_dir/sessions.json",   '{}');
write_file("$data_dir/activities.json", '{}');
write_file("$data_dir/shed.json",       '{}');
write_file("$data_dir/seasons.json",    '{"s1":{"id":"s1","label":"Test","status":"active","day":1,"length":30}}');

use MagicMountain::Model::Character;
my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
$chars->create(name => 'alice', account_id => 'a1', season_id => 's1',
    score => 0, scrap => 0, action_points => 0, action_points_max => 15)->save;

use MagicMountain;
my $app = MagicMountain->new;
$app->startup;

$app->commands->run('advance_day');

$chars->load;
my ($char) = @{ $chars->find(sub { $_[0]->{name} eq 'alice' }) };
is($char->getCol('action_points'), 15, 'AP refreshed to 15');
is($char->getCol('score'), 0, 'score unchanged');

$app->commands->run('advance_day');
$chars->load;
($char) = @{ $chars->find(sub { $_[0]->{name} eq 'alice' }) };
is($char->getCol('action_points'), 15, 'AP still 15 after second advance');

my $season = $app->active_season;
is($season->getCol('day'), 3, 'day advanced to 3');

done_testing;
