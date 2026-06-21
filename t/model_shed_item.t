use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib");
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::ShedItem');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $shed = MagicMountain::Model::ShedItem->new(file => $file);

subtest 'create and save' => sub {
    my $item = $shed->create(
        char_id             => 'char-1',
        artifact_id         => 'thermal_box_001',
        original_value      => 20,
        decayed_value       => 20,
        condition           => 'fresh',
        estimated_value_min => 16,
        estimated_value_max => 24,
    );
    is($item->getCol('char_id'), 'char-1', 'char_id set');
    is($item->getCol('artifact_id'), 'thermal_box_001', 'artifact_id set');
    is($item->getCol('condition'), 'fresh', 'condition set');
    is($item->getCol('id'), undef, 'no id before save');

    $item->save;
    ok($item->getCol('id'), 'id assigned after save');
};

subtest 'load by id' => sub {
    my $item = $shed->create(char_id => 'char-2', artifact_id => 'crystal_chime_001');
    $item->save;
    my $id = $item->getCol('id');

    my $loaded = $shed->get($id);
    ok($loaded, 'loaded by id');
    is($loaded->getCol('artifact_id'), 'crystal_chime_001', 'artifact_id preserved');
};

subtest 'find by char_id' => sub {
    my $results = $shed->find(sub { $_[0]->{char_id} eq 'char-1' });
    ok(@$results >= 1, 'found items for char-1');
};

subtest 'delete' => sub {
    my $item = $shed->create(char_id => 'char-3', artifact_id => 'test');
    $item->save;
    my $id = $item->getCol('id');

    $item->delete;
    my $loaded = $shed->get($id);
    is($loaded, undef, 'deleted item gone');
};

done_testing;
