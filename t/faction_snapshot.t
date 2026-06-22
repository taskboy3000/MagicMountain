use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::FactionSnapshot');

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;

subtest 'create and query snapshots' => sub {
    my $model = MagicMountain::Model::FactionSnapshot->new(
        file => "$data_dir/faction_snapshots.json",
    );

    $model->create(
        season_id         => 's1',
        day               => 1,
        faction_id        => 'syndicate',
        influence         => 10,
        artifacts_received => 1,
        intake_by_trait   => { thermal => 1 },
    )->save;

    $model->create(
        season_id         => 's1',
        day               => 1,
        faction_id        => 'faculty',
        influence         => 5,
        artifacts_received => 1,
        intake_by_trait   => { signal => 1 },
    )->save;

    $model->create(
        season_id         => 's1',
        day               => 2,
        faction_id        => 'syndicate',
        influence         => 25,
        artifacts_received => 2,
        intake_by_trait   => { thermal => 2 },
    )->save;

    $model->load;

    my $all = $model->find(sub { 1 });
    is(scalar @$all, 3, '3 snapshot rows');

    my $syndicate = $model->find(sub { $_[0]->{faction_id} eq 'syndicate' });
    is(scalar @$syndicate, 2, '2 syndicate snapshots');

    my @by_day = sort { $a->getCol('day') <=> $b->getCol('day') } @$syndicate;
    is($by_day[0]->getCol('influence'), 10, 'day 1 influence');
    is($by_day[1]->getCol('influence'), 25, 'day 2 influence');
};

subtest 'columns include default + snapshot fields' => sub {
    my $model = MagicMountain::Model::FactionSnapshot->new(
        file => "$data_dir/faction_snapshots.json",
    );
    my $cols = $model->columns;
    ok(grep { $_ eq 'season_id' } @$cols, 'has season_id');
    ok(grep { $_ eq 'day' } @$cols, 'has day');
    ok(grep { $_ eq 'faction_id' } @$cols, 'has faction_id');
    ok(grep { $_ eq 'influence' } @$cols, 'has influence');
    ok(grep { $_ eq 'artifacts_received' } @$cols, 'has artifacts_received');
    ok(grep { $_ eq 'intake_by_trait' } @$cols, 'has intake_by_trait');
};

done_testing;
