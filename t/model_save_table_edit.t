use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model');

# Reproduce: call save() after directly mutating the table hashref.
# save() should not re-load from disk (undoing in-memory changes)
# and should not inject an empty-row entry.

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, <<'JSON');
{
  "existing-id": {
    "id": "existing-id",
    "name": "alice",
    "createdAt": 1000,
    "updatedAt": 1000
  }
}
JSON

my $model = MagicMountain::Model->new(file => $file);
$model->load;

# Add a second record via the table hashref directly (simulating what
# a bulk operation like end_season does when deleting items)
$model->table->{'new-id'} = {
    id => 'new-id', name => 'bob', createdAt => 2000, updatedAt => 2000,
};

# Now call save(). The bug: save() calls load() which re-reads the file
# (restoring "existing-id" but losing "new-id"), then adds $self->row
# (which is empty on a global instance) as a junk entry.
$model->save;

# Re-read file and check
$model->load;
my $keys = [ sort keys %{ $model->table } ];

is(scalar @$keys, 2, 'two records after save — direct table add preserved');
is($keys->[0], 'existing-id', 'existing record still present');
is($keys->[1], 'new-id', 'directly added record still present');

# Check no junk entry with only default columns
for my $id (@$keys) {
    my $row = $model->table->{$id};
    ok(exists $row->{name}, "record $id has 'name' column");
}

# Also test: delete from table and save
$model->load;  # fresh load
delete $model->table->{'existing-id'};
$model->save;

$model->load;
$keys = [ sort keys %{ $model->table } ];
is(scalar @$keys, 1, 'one record after delete + save');
is($keys->[0], 'new-id', 'only new-id remains');

done_testing;
