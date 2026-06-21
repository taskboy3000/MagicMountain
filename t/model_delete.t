use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib");
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::Character');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $model = MagicMountain::Model::Character->new(file => $file);

subtest 'delete with explicit id' => sub {
    my $c = $model->create(name => 'alice', account_id => 'a1', season_id => 's1');
    $c->save;
    my $id = $c->getCol('id');
    ok($id, 'id assigned');

    my $result = $model->delete($id);
    ok($result, 'delete returns true');

    my $loaded = $model->get($id);
    is($loaded, undef, 'row gone after delete');
};

subtest 'delete with no arg on instance' => sub {
    my $c = $model->create(name => 'bob', account_id => 'a2', season_id => 's1');
    $c->save;
    my $id = $c->getCol('id');

    my $result = $c->delete;
    ok($result, 'instance delete returns true');

    my $loaded = $model->get($id);
    is($loaded, undef, 'row gone after instance delete');
};

subtest 'delete on unsaved instance' => sub {
    my $c = $model->create(name => 'carol', account_id => 'a3', season_id => 's1');
    is($c->getCol('id'), undef, 'no id before save');

    my $result = $c->delete;
    is($result, undef, 'delete on unsaved returns undef');
};

subtest 'delete backward compatible with explicit id' => sub {
    my $c = $model->create(name => 'dave', account_id => 'a4', season_id => 's1');
    $c->save;
    my $id = $c->getCol('id');

    my $result = $model->delete($id);
    ok($result, 'delete with id still works');
};

done_testing;
