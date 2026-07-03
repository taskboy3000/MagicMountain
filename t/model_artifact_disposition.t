use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::ArtifactDisposition');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $d = MagicMountain::Model::ArtifactDisposition->new(file => $file);

isa_ok($d, 'MagicMountain::Model::ArtifactDisposition');

subtest 'create and read disposition' => sub {
    my $rec = $d->create(
        season_id       => 'season-1',
        player_id       => 'player-1',
        faction_id      => 'syndicate',
        season_day      => 4,
        value_awarded   => 42,
        artifact_snapshot => {
            artifact_id => 'thermal_box_001',
            original_value => 20,
            decayed_value  => 18,
            condition  => 'settling',
            days_in_shed => 2,
            instability => 8,
            stage   => 'strained',
            push_count => 3,
            has_evolved => \0,
            behaviors => ['thermal', 'power'],
        },
        standing_delta  => 2,
        influence_delta => 42,
        narrative_hooks => {},
    );
    $rec->save;

    ok($rec->getCol('id'), 'has UUID');
    is($rec->getCol('faction_id'), 'syndicate', 'faction_id stored');
    is($rec->getCol('value_awarded'), 42, 'value_awarded stored');
    is($rec->getCol('standing_delta'), 2, 'standing_delta stored');
    is($rec->getCol('season_day'), 4, 'season_day stored');
};

subtest 'artifact snapshot is a hash' => sub {
    my $rec = $d->create(
        season_id  => 'season-1',
        player_id  => 'player-1',
        faction_id => 'faculty',
        season_day => 7,
        value_awarded => 15,
        artifact_snapshot => { artifact_id => 'void_core_001' },
        standing_delta  => 1,
        influence_delta => 15,
        narrative_hooks => {},
    );
    $rec->save;

    my $snap = $rec->getCol('artifact_snapshot');
    is(ref $snap, 'HASH', 'artifact_snapshot is a hash');
    is($snap->{artifact_id}, 'void_core_001', 'snapshot contains artifact_id');
};

subtest 'load back from file' => sub {
    $d->load;
    my $results = $d->find(sub { $_[0]->{faction_id} eq 'syndicate' });
    is(scalar @$results, 1, 'found syndicate disposition');
    is($results->[0]->getCol('value_awarded'), 42, 'value preserved through save/load');
};

done_testing;
