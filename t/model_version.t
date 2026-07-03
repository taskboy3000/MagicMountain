use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Model');

subtest 'save creates and increments version' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, '{}');
    my $m = MagicMountain::Model->new(file => $file);
    my $obj = $m->create(createdAt => 10);
    $obj->save;
    my $data = decode_json(read_file($file));
    ok(exists $data->{_version}, '_version key present after save');
    is($data->{_version}, 1, 'first save sets version to 1');
    my $id = $obj->getCol('id');
    ok(exists $data->{$id}, 'record present');

    $obj->save;
    $data = decode_json(read_file($file));
    is($data->{_version}, 2, 'second save increments version');
};

subtest 'version survives reload cycle' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, '{}');
    my $m = MagicMountain::Model->new(file => $file);
    $m->create(createdAt => 20)->save;
    my $data = decode_json(read_file($file));
    my $v1 = $data->{_version};
    $m->load;
    $data = decode_json(read_file($file));
    is($data->{_version}, $v1, 'version unchanged after load');
};

subtest 'unversioned file gets version on first save' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, encode_json({ existing => { id => 'existing', createdAt => 1, updatedAt => 1 } }));
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    my $obj = $m->create(createdAt => 30);
    $obj->save;
    my $data = decode_json(read_file($file));
    is($data->{_version}, 1, 'unversioned file gets version 1 on first save');
    ok(exists $data->{existing}, 'existing record preserved');
    ok(exists $data->{$obj->getCol('id')}, 'new record present');
};

subtest 'stale write transparently reloads and retries' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, '{}');
    my $m = MagicMountain::Model->new(file => $file);
    $m->create(createdAt => 40)->save;
    # Load into a second model simulating a separate request
    my $m2 = MagicMountain::Model->new(file => $file);
    $m2->load;
    # Record the version that m2 loaded
    my $loaded_ver = $m2->{_loaded_version};
    # Someone else modifies the file (simulating maintenance)
    my $data = decode_json(read_file($file));
    $data->{_version}++;
    write_file($file, encode_json($data));
    # Now try to save from m2 — should reload and succeed, not die
    my $obj2 = $m2->create(createdAt => 50);
    $obj2->save;
    pass('stale write silently recovered via reload');
    # Verify the file has the new record
    $data = decode_json(read_file($file));
    is($data->{_version}, $loaded_ver + 2, 'version incremented by two (external + our save)');
    ok(exists $data->{$obj2->getCol('id')}, 'record present after stale-write recovery');
};

subtest 'delete preserves version' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, '{}');
    my $m = MagicMountain::Model->new(file => $file);
    my $obj = $m->create(createdAt => 60);
    $obj->save;
    my $v1 = (decode_json(read_file($file)))->{_version};
    $m->delete($obj->getCol('id'));
    my $data = decode_json(read_file($file));
    is($data->{_version}, $v1 + 1, 'delete increments version');
    ok(!exists $data->{$obj->getCol('id')}, 'record deleted');
};

subtest 'corrupt file in version pre-read dies' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($file, 'not valid json');
    my $m = MagicMountain::Model->new(file => $file);
    eval { $m->save };
    like($@, qr/version read: bad JSON/, 'corrupt file detected in version pre-read');
};

done_testing;
