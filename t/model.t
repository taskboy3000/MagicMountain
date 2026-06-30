use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib");

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);
use UUID::Tiny qw(:std);

use_ok('MagicMountain::Model');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);

subtest 'file accessor dies without path' => sub {
    my $m = MagicMountain::Model->new;
    eval { $m->file };
    like($@, qr/Add a path to the state file/, 'file dies without path');
};

subtest 'log default accessor' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    my $log = $m->log;
    is(ref $log, 'CODE', 'log default returns a coderef');
};

subtest 'table default' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    is_deeply($m->table, {}, 'table default is empty hashref');
};

subtest 'row default' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    is_deeply($m->row, {}, 'row default is empty hashref');
};

subtest 'defaultColumns' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    is_deeply($m->defaultColumns, [qw{id updatedAt createdAt}], 'defaultColumns');
};

subtest 'columns defaults to defaultColumns' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    is_deeply($m->columns, [qw{id updatedAt createdAt}], 'columns inherits defaults');
};

subtest 'getCol - valid column' => sub {
    my $m = MagicMountain::Model->new(file => $file, row => { id => 'abc', updatedAt => 1, createdAt => 2 });
    is($m->getCol('id'), 'abc', 'getCol returns value for valid column');
    is($m->getCol('updatedAt'), 1, 'getCol returns updatedAt');
    is($m->getCol('createdAt'), 2, 'getCol returns createdAt');
};

subtest 'getCol - invalid column dies' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    eval { $m->getCol('nonexistent') };
    like($@, qr/assert: no such column 'nonexistent'/, 'getCol dies on unknown column');
};

subtest 'setCol - valid column' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->setCol('updatedAt', 42);
    is($m->row->{updatedAt}, 42, 'setCol sets value');
};

subtest 'setCol - default undef' => sub {
    my $m = MagicMountain::Model->new(file => $file, row => { id => 'x', updatedAt => 99, createdAt => 1 });
    $m->setCol('updatedAt');
    is($m->row->{updatedAt}, undef, 'setCol defaults to undef');
};

subtest 'setCol - invalid column dies' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    eval { $m->setCol('bogus', 1) };
    like($@, qr/assert: no such column 'bogus'/, 'setCol dies on unknown column');
};

subtest 'load - file exists' => sub {
    my $data = { 'id1' => { id => 'id1', updatedAt => 100, createdAt => 50 } };
    write_file($file, encode_json($data));
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    is_deeply($m->table, $data, 'load populates table from file');
};

subtest 'load - file does not exist' => sub {
    my $missing = '/tmp/missing_model_test_' . $$ . '.json';
    unlink $missing;
    my $m = MagicMountain::Model->new(file => $missing);
    my $result = $m->load;
    is($result, 1, 'load returns 1 when file missing');
    is_deeply($m->table, {}, 'table stays empty');
    unlink $missing;
};

subtest 'load - bad JSON dies' => sub {
    write_file($file, 'not json at all');
    my $m = MagicMountain::Model->new(file => $file);
    eval { $m->load };
    like($@, qr/JSON DECODE FAILURE/, 'load dies on bad JSON');
    write_file($file, '{}');
};

subtest '_saveTable writes to atomic tmp then renames' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    my $id = create_uuid();
    $m->table->{$id} = { id => $id, updatedAt => 10, createdAt => 5 };
    $m->_saveTable;
    my $raw = read_file($file);
    my $data = decode_json($raw);
    ok(exists $data->{$id}, 'saved table contains record');
    is_deeply($data->{$id}, { id => $id, updatedAt => 10, createdAt => 5 }, 'saved data matches');
};

subtest 'save - new record gets id, createdAt, updatedAt' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    $m->row({ updatedAt => 0, createdAt => 0 });
    delete $m->row->{id};
    $m->save;
    ok($m->row->{id}, 'save assigns a UUID id');
    ok($m->row->{createdAt}, 'save sets createdAt');
    ok($m->row->{updatedAt}, 'save sets updatedAt');
    my $stored = decode_json(read_file($file));
    ok(exists $stored->{$m->row->{id}}, 'record persisted in table');
};

subtest 'save - existing record preserves id and createdAt' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    my $id = create_uuid();
    my $ts = time() - 100;
    $m->row({ id => $id, createdAt => $ts, updatedAt => 0 });
    $m->save;
    is($m->row->{id}, $id, 'id preserved');
    is($m->row->{createdAt}, $ts, 'createdAt preserved');
    ok($m->row->{updatedAt} > 0, 'updatedAt updated');
};

subtest 'create - valid columns' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    my $obj = $m->create(createdAt => 999);
    ok(ref $obj eq 'MagicMountain::Model', 'create');
    ok($obj->getCol('createdAt') == 999, 'fetch col value');
};

subtest 'create - invalid column dies' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    eval { $m->create(bogus => 1) };
    # diag("Got> $@");
    like($@, qr/column 'bogus'/, 'create dies on unknown column');
};

subtest 'get - found' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    my $obj = $m->create(createdAt => 123);
    $obj->save;
    my $id = $obj->row->{id};
    my $found = $m->get($id);
    ok($found, 'get returns truthy for existing record');
    is($found->getCol('id'), $id, 'get returns correct id');
    is($found->row->{createdAt}, 123, 'get returns correct data');
};

subtest 'get - not found' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    my $result = $m->get('nonexistent_id');
    is($result, undef, 'get returns undef for missing record');
};

subtest 'get - returns shallow copy of row' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    my $obj = $m->create(createdAt => 555);
    $obj->save;
    my $found = $m->get($obj->getCol('id'));
    isnt(
        $found->row, 
        $m->table->{$obj->getCol('id')}, 
        'get returns a shallow copy of row, not same ref'
    );
};

subtest 'all - returns clone' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->create(createdAt => 10);
    my $clone = $m->all;
    isnt($clone, $m->table, 'all returns a different ref');
    is(scalar keys %$clone, scalar keys %{$m->table}, 'clone has same key count');
};

subtest 'delete - found' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    my $obj = $m->create(createdAt => 777);
    $obj->save;
    my $id = $obj->getCol('id');
    my $result = $m->delete($id);
    ok($result, 'delete returns truthy for found record');
    my $stored = decode_json(read_file($file));
    ok(!exists $stored->{$id}, 'deleted record absent from file');
};

subtest 'delete - not found' => sub {
    my $m = MagicMountain::Model->new(file => $file);
    $m->load;
    my $result = $m->delete('no_such_id');
    is($result, undef, 'delete returns undef for missing record');
};

subtest 'subclass with extra columns' => sub {
    package MythicalModel;
    use Mojo::Base 'MagicMountain::Model', '-signatures';
    has columns => sub ($self) {
        my $cols = $self->defaultColumns;
        return [ @$cols, 'name', 'power' ];
    };
    package main;

    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $mm = MythicalModel->new(file => $f2);
    is_deeply($mm->columns, [qw{id updatedAt createdAt name power}], 'subclass columns extend defaults');
    my $obj = $mm->create(name => 'hero', power => 42);
    $obj->save;
    is($obj->row->{name}, 'hero', 'subclass create sets extra column');
    is($obj->row->{power}, 42, 'subclass create sets second extra column');
    my $found = $mm->get($obj->getCol('id'));
    is($found->row->{name}, 'hero', 'get retrieves subclass column');
    eval { $mm->create(sekrit => 1); $mm->save; 1 };
    like($@, qr/column 'sekrit'/, 'subclass rejects unknown column');
};

subtest 'find - CODE match found' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    my $obj = $m->create(createdAt => 123);
    $obj->save;
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} == 123 });
    is(scalar @$results, 1, 'find CODE returns one match');
    is($results->[0]->getCol('id'), $obj->getCol('id'), 'find CODE returns correct record');
};

subtest 'find - CODE no match' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 100)->save;
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} == 999 });
    is_deeply($results, [], 'find CODE returns empty arrayref when no match');
};

subtest 'find - CODE multiple matches' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 10)->save;
    $m->create(createdAt => 20)->save;
    $m->create(createdAt => 30)->save;
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} > 15 });
    is(scalar @$results, 2, 'find CODE returns multiple matches');
};

subtest 'find - CODE results are Model objects' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 42)->save;
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} == 42 });
    is(ref $results->[0], 'MagicMountain::Model', 'find CODE returns Model object');
    is($results->[0]->getCol('createdAt'), 42, 'find CODE result supports getCol');
};

subtest 'find - CODE results are shallow copies' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    my $obj = $m->create(createdAt => 88);
    $obj->save;
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} == 88 });
    isnt($results->[0]->row, $m->table->{$obj->getCol('id')}, 'find CODE result row is a shallow copy');
};

subtest 'find - HASH single column regex match' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 123)->save;
    my $results = $m->find({ createdAt => qr/1/ });
    is(scalar @$results, 1, 'find HASH matches single regex');
    is($results->[0]->getCol('createdAt'), 123, 'find HASH returns correct record');
};

subtest 'find - HASH no match' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 100)->save;
    my $results = $m->find({ createdAt => qr/^9/ });
    is_deeply($results, [], 'find HASH returns empty arrayref when no match');
};

subtest 'find - HASH all columns must match' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 100)->save;
    $m->create(createdAt => 200)->save;
    my $results = $m->find({ createdAt => qr/00/, updatedAt => qr/./ });
    is(scalar @$results, 2, 'find HASH matches when all columns match');
};

subtest 'find - HASH one column fails excludes record' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    $m->create(createdAt => 100)->save;
    $m->create(createdAt => 200)->save;
    my $results = $m->find({ createdAt => qr/^2/ });
    is(scalar @$results, 1, 'find HASH excludes records that fail one column');
    is($results->[0]->getCol('createdAt'), 200, 'find HASH returns only matching record');
};

subtest 'find - empty table returns empty arrayref' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    my $results = $m->find(sub { my ($row) = @_; 1 });
    is_deeply($results, [], 'find on empty table returns empty arrayref');
};

subtest 'find - invalid criteria dies' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    eval { $m->find('invalid') };
    like($@, qr/assert - unsupport criteria/, 'find dies on invalid criteria type');
};

subtest 'find - reads persisted data from disk' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    my $id = create_uuid_as_string();
    write_file($f2, encode_json({ $id => { id => $id, createdAt => 555, updatedAt => 555 } }));
    my $m = MagicMountain::Model->new(file => $f2);
    my $results = $m->find(sub { my ($row) = @_; $row->{createdAt} == 555 });
    is(scalar @$results, 1, 'find reads persisted data from disk');
    is($results->[0]->getCol('id'), $id, 'find returns correct record from disk');
};

subtest 'reload re-reads modified file' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, encode_json({ a1 => { id => 'a1', createdAt => 1, updatedAt => 1 } }));
    my $m = MagicMountain::Model->new(file => $f2);
    $m->load;
    is(scalar keys %{$m->table}, 1, 'one record after load');
    write_file($f2, encode_json({ b1 => { id => 'b1', createdAt => 2, updatedAt => 2 } }));
    $m->reload;
    is(scalar keys %{$m->table}, 1, 'one record after reload');
    ok($m->table->{b1}, 'reload sees new record');
    ok(!$m->table->{a1}, 'reload drops old record');
};

subtest 'reload invalidates shared-table siblings' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, encode_json({ x => { id => 'x', createdAt => 1, updatedAt => 1 } }));
    my $m1 = MagicMountain::Model->new(file => $f2);
    my $m2 = $m1->create(createdAt => 99);  # shares same table
    $m1->load;
    is(scalar keys %{$m1->table}, 1, 'm1 sees one record');
    write_file($f2, encode_json({ y => { id => 'y', createdAt => 2, updatedAt => 2 } }));
    $m1->reload;
    is(scalar keys %{$m2->table}, 1, 'm2 (shared table) sees same data via m1 reload');
    ok($m2->table->{y}, 'm2 sees new record through shared table ref');
};

subtest 'validate_save base method is a no-op' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    is($m->validate_save, 1, 'base validate_save returns 1');
};

subtest 'timing instrumentation does not crash' => sub {
    my ($fh2, $f2) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($f2, '{}');
    my $m = MagicMountain::Model->new(file => $f2);
    my $obj = $m->create(createdAt => 42);
    $obj->save;
    $m->load;
    $m->delete($obj->getCol('id'));
    pass('load, save, delete with timing instrumentation did not crash');
};

done_testing;