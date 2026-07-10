use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Season;

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;
$ENV{MM_SKIP_SEASON_CHECK} = 1;

my $season_obj = MagicMountain::Model::Season->new(file => "$data_dir/seasons.json");

# Create 5 archived seasons (simulating Seasons 1-5 all finalized)
for my $i (1 .. 5) {
    $season_obj->create(
        id     => "s$i",
        label  => "Season $i",
        status => 'archived',
        day    => 30,
        length => 30,
    )->save;
}

use MagicMountain;
my $app = MagicMountain->new;
$app->startup;

subtest 'ensureActiveSeason skips existing labels after gap' => sub {
    $app->ensureActiveSeason;
    $app->seasons->load;
    my $active = $app->active_season;
    ok($active, 'ensureActiveSeason created an active season');
    is($active->getCol('label'), 'Season 6', 'label is max+1, not count-based duplicate');
};

subtest 'ensureActiveSeason is idempotent' => sub {
    $app->ensureActiveSeason;
    my $all = $app->seasons->all;
    my @active = grep { $_->{status} eq 'active' } values %$all;
    is(scalar @active, 1, 'only one active season after second call');
    is($active[0]->{label}, 'Season 6', 'label unchanged on second call');
};

done_testing;
