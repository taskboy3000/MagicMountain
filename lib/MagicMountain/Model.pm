package MagicMountain::Model;
# This is a base class for all the objects that need persisting


use File::Slurp qw(read_file write_file);
use File::Spec;
use IO::Handle;
use Modern::Perl;
use Mojo::Base '-base', '-signatures';
use Mojo::JSON ('encode_json', 'decode_json');
use Time::HiRes;
use UUID::Tiny (':std');

my %_mtime_for;

has 'file' => sub ($self) {
    die("Add a path to the state file");
}; # A required file path to persist too

# The intention is for the app class MagicMountain to instantial one of every model class like:
# MagicMountain::Model::Foo->new(file => 'table.json', log => $self->log);
has 'log' => sub ($self) {
    sub ($alertLevel, @payload) { say "DEFAULT LOGGER[$alertLevel]> " . join(',', @payload) };   
}; # An optional logger function


# This is the entire table:
#. { id => {fullRecord} }
has table => sub ($self) {
    return {}
};

# This is a specific record in the table
#   { id => , ... createdAt }
has 'row' => sub ($self) {
    return {}
};

# These columns are managed by Model.pm and should not be assigned by subclasses
has defaultColumns => sub ($self) {
    return [qw{id updatedAt createdAt}];
};

# Usage in subclasses:
#   has columns => sub ($self) {
#       my $cols = $self->defaultColumns;
#       return [ @$cols, 'col1', 'col2', 'col3' ];    
#   }
has columns => sub ($self) {
    return $self->defaultColumns;
};

sub getCol ($self, $columnName) {
    if (grep {$_ eq $columnName} @{$self->columns}) {
        return $self->row->{$columnName}
    }
    die ("assert: no such column '$columnName' declared on " . ref $self);
}


sub setCol ($self, $columnName, $optionalValue=undef) {
    if (grep {$_ eq $columnName} @{$self->columns}) {
        $self->validate($columnName, $optionalValue);
        return $self->row->{$columnName} = $optionalValue
    }
    die ("assert: no such column '$columnName' declared on " . ref $self);
}

sub nullCol ($self, $columnName) {
    if (grep {$_ eq $columnName} @{$self->columns}) {
        delete $self->row->{$columnName};
        return 1;
    }
    die ("assert: no such column '$columnName' declared on " . ref $self);
}

sub _log_debug ($self, @msg) {
    my $log = $self->log;
    if (ref $log eq 'CODE') {
        $log->('debug', ref($self), @msg);
    } elsif (eval { $log->can('debug') }) {
        $log->debug(ref($self), @msg);
    }
}

sub validate ($self, $columnName, $value) { 1 }  # no-op base

sub validate_save ($self) { 1 }

sub reload ($self) {
    delete $_mtime_for{0+$self->table};
    $self->load;
}

sub hasCol ($self, $columnName) {
    return grep {$_ eq $columnName} @{$self->columns};
}

# Load all data from $self->file
sub load ($self) {
    my $start = Time::HiRes::time;
    my $key = 0+$self->table;
    my $stat = -e $self->file ? [stat $self->file] : undef;
    my $sig = $stat ? "$stat->[9]:$stat->[7]" : '0:0';  # mtime:size
    return 1 if defined $_mtime_for{$key} && $_mtime_for{$key} eq $sig;

    if ($stat) {
        my $content = read_file($self->file);
        my $data;
        eval {
            $data = decode_json($content);
            1;
        } or do {
            die("JSON DECODE FAILURE: $@");
        };
        $self->{_loaded_version} = delete $data->{_version};
        %{ $self->table } = %{ $data };
    }

    $_mtime_for{$key} = $sig;
    my $elapsed = (Time::HiRes::time - $start) * 1000;
    $self->_log_debug('load', sprintf('%.1fms', $elapsed),
        scalar(keys %{$self->table}), 'records') if $stat;
    return 1;
}

# Only saves the table in its current form
sub _saveTable ($self) {
    my $start = Time::HiRes::time;

    my $version = ($self->_read_version_from_disk // 0) + 1;
    my $json = encode_json({ _version => $version, %{ $self->table } });

    my $tmpFile = $self->file . "$$.tmp";
    open my $fh, '>', $tmpFile or die "can't write $tmpFile: $!";
    my $written = syswrite $fh, $json;
    die "syswrite short write ($written / " . length($json) . ")" if $written != length($json);
    $fh->sync or die "fsync $tmpFile failed: $!";
    close $fh;
    rename $tmpFile, $self->file or die "rename failed: $!";

    my $dir = (File::Spec->splitpath($self->file))[1];
    if (open my $dfh, '<', $dir) {
        eval { $dfh->sync };
        warn "directory fsync failed: $@" if $@;
        close $dfh;
    }

    my $stat = [stat $self->file];
    $_mtime_for{0+$self->table} = "$stat->[9]:$stat->[7]";

    my $elapsed = (Time::HiRes::time - $start) * 1000;
    $self->_log_debug('_saveTable', sprintf('%.1fms', $elapsed),
        scalar(keys %{$self->table}), 'records');
    return 1;
}

sub _read_version_from_disk ($self) {
    return unless -e $self->file;
    my $content = read_file($self->file);
    my $data = eval { decode_json($content) };
    die "version read: bad JSON in " . $self->file . ": $@" if $@;
    return $data->{_version};
}

# Let the caller persist this object if desired
sub create ($self, %params) {
    for my $key (keys %params) {
        if (!$self->hasCol($key)) {
            die((ref $self) . " does not have column '" . $key . "'\n");
        } 
    }
    my $new = $self->new(
        file => $self->file,
        log => $self->log,
        table => $self->table,
        row => \%params
    );
    $new->{_loaded_version} = $self->{_loaded_version};
    return $new;
}

# Persist this one $self->data record to $self->file
sub save ($self) {
    my $key = 0+$self->table;
    my $disk_ver = $self->_read_version_from_disk;
    if (defined $self->{_loaded_version} && defined $disk_ver
        && $self->{_loaded_version} != $disk_ver) {
        $self->reload;
    }
    my $stat = -e $self->file ? [stat $self->file] : undef;
    my $sig = $stat ? "$stat->[9]:$stat->[7]" : '0:0';
    $self->load unless defined $_mtime_for{$key} && $_mtime_for{$key} eq $sig;
    return $self->_saveTable unless keys %{ $self->row };

    if (!$self->row->{id}) {
        $self->row->{id} = create_uuid_as_string();
    }

    if (!$self->row->{createdAt}) {
        $self->row->{createdAt} = time();
    }

    $self->row->{updatedAt} = time();

    # we are updating the table
    $self->table->{$self->row->{id}} = $self->row;
    $self->validate_save;
    return $self->_saveTable;
}




sub get ($self, $id) {
    $self->load;
    if ($id && $self->table->{$id}) {
        my $obj = $self->new(
            file => $self->file,
            log => $self->log,
            table => $self->table,
            row => { %{ $self->table->{$id} }}
        );
        $obj->{_loaded_version} = $self->{_loaded_version};
        return $obj;
    }
    return;
}

sub all ($self) {
    $self->load;
    my $clone = { %{$self->table} };
    return $clone;
}

# Abstract:
#   $model->find(sub ($row) { $row->{col1} eq 'foo' && $row->{col2} })
#     or 
#  $model->find({col1 => qr/foo/, col2 => qr/bar/})
#
#  Returns an array ref of models
sub find ($self, $codeRefOrHashRef) {
    $self->load;
    my @found;
    if (ref $codeRefOrHashRef eq 'CODE') {
        # Was given a truth test that must pass for many column values in this row
        for my $row ( values %{$self->table} ) {
            if ($codeRefOrHashRef->($row)) {
                my $record = $self->get($row->{'id'});
                push @found, $record;
            }
        }
        return \@found;
    } elsif (ref $codeRefOrHashRef eq 'HASH') {
        for my $row (values %{$self->table} ) {
            my $matched = 1;
            while (my ($column, $regex) = each %{$codeRefOrHashRef}) {
                my $colValue = $row->{$column};
                $matched &&= ($colValue =~ $regex ? 1 : 0);
            }

            if ($matched) {
                my $record = $self->get($row->{'id'});
                push @found, $record;
            }
        }
        return \@found;
    } else {
        die("assert - unsupport criteria");
    }
}


sub delete ($self, $id = undef) {
    $id //= $self->getCol('id');
    return unless $id;

    $self->load;

    if ($self->table->{$id}) {
        delete $self->table->{$id};
        return $self->_saveTable;
    }
    return;
}

1;

__END__

=head1 NAME

MagicMountain::Model - Base persistence class for Magic Mountain records

=head1 SYNOPSIS

  # Define a subclass
  package MagicMountain::Model::Account;
  use Mojo::Base 'MagicMountain::Model', '-signatures';

  has columns => sub ($self) {
      my $cols = $self->defaultColumns;
      return [ @$cols, qw(username passwordHash disabled) ];
  };

  # Later, in application code:
  my $accts = MagicMountain::Model::Account->new(
      file => '/path/to/accounts.json',
      log  => sub ($level, @msg) { say "[$level] @msg" },
  );

  # Create a new record (in-memory only):
  my $record = $accts->create(username => 'alice', passwordHash => '...');

  # Persist to disk:
  $record->save;

  # Retrieve by ID:
  my $alice = $accts->get($record->row->{id});

  # Query with a code reference:
  my $found = $accts->find(sub ($row) { $row->{username} eq 'alice' });

  # Query with a hash of regexes:
  my $active = $accts->find({ disabled => qr/^0$/ });

  # Get all records:
  my $all = $accts->all;

  # Delete a record:
  $accts->delete($id);

=head1 DESCRIPTION

C<MagicMountain::Model> is the base class for all persisted objects in the
Magic Mountain game. It provides a simple JSON file-backed key-value store
where each file holds a hash of records keyed by UUID.

Each subclass declares its own columns (via the C<columns> attribute) and
inherits CRUD operations, lazy-loading, and atomic file writes.

=head2 Persistence Strategy

Data is stored as a single JSON object per file:

  {
      "uuid-1": { "id": "uuid-1", "createdAt": 1700000000, "updatedAt": 1700000100, ... },
      "uuid-2": { "id": "uuid-2", "createdAt": 1700000001, "updatedAt": 1700000101, ... }
  }

Writes are atomic: data is written to a temporary file (C<< <file>$$.tmp >>)
then renamed over the target. This prevents corruption on crash or power loss.

The C<load> method is idempotent and uses file mtime to avoid re-reading
unchanged data.

=head2 Lifecycle Summary

  1. Instantiate a model object (pointing at a JSON file).
  2. Call C<create(%params)> to build an in-memory record.
  3. Call C<< $record->save >> to persist (auto-assigns C<id>, C<createdAt>,
     C<updatedAt>).
  4. Retrieve records with C<get>, C<all>, or C<find>.
  5. Delete with C<delete>.

=head1 ATTRIBUTES

=head2 file

  has 'file' => sub ($self) { die("Add a path to the state file") };

Required. The filesystem path to the JSON file used for persistence. Must be
provided to the constructor. Dies on access if not set.

=head2 log

  has 'log' => sub ($self) {
      sub ($alertLevel, @payload) { say "DEFAULT LOGGER[$alertLevel]> " . join(',', @payload) };
  };

Optional. A coderef called as C<< $log->($level, @messages) >>. Defaults to a
simple C<say>-based logger.

=head2 table

  has table => sub ($self) { return {} };

The in-memory hashref of all records: C<< { $id => \%record, ... } >>.
Shared across all instances created from the same model object so that
in-memory changes are visible to siblings without re-reading the file.

=head2 row

  has 'row' => sub ($self) { return {} };

The current record's data hashref. Populated by C<create>, C<get>, and C<find>.
Access individual fields via C<getCol> / C<setCol> or directly through the
hashref.

=head2 columns

  has columns => sub ($self) { return $self->defaultColumns };

Override in subclasses to declare the valid column names. Should begin with the
result of C<defaultColumns> and append custom columns:

  has columns => sub ($self) {
      my $cols = $self->defaultColumns;
      return [ @$cols, qw(col1 col2 col3) ];
  };

=head2 defaultColumns

  has defaultColumns => sub ($self) { return [qw{id updatedAt createdAt}] };

Returns the column list managed by the base class: C<id>, C<updatedAt>,
C<createdAt>. Subclass C<columns> overrides should include these.

=head1 METHODS

=head2 getCol

  my $val = $model->getCol('username');

Returns the value of the named column from the current C<row>. Dies if the
column name is not declared in C<columns>.

=head2 setCol

  $model->setCol('username', 'bob');

Sets the value of the named column on the current C<row>. Dies if the column
name is not declared. Returns the new value.

=head2 nullCol

  $model->nullCol('faction_state');

Removes the named column from the current C<row> entirely (C<delete> from the
row hash). Unlike C<setCol($col, undef)>, this prevents the key from appearing
as C<null> in the persisted JSON. Dies if the column name is not declared.
Returns 1.

=head2 hasCol

  if ($model->hasCol('faction')) { ... }

Returns true if the named column is declared in C<columns>.

=head2 load

  $model->load;

Reads the JSON file from disk and populates C<table>. Skips re-reading if the
file's mtime has not changed. Called automatically by C<save>, C<get>,
C<all>, C<find>, and C<delete>, so explicit calls are rarely needed.

Dies on JSON decode failure.

=head2 create

  my $record = $model->create(username => 'alice', score => 100);

Returns a B<new> model instance (same C<file>, C<log>, C<table>) with
C<row> populated from the given parameters. The record is B<not> persisted
until C<save> is called on the returned object.

Dies if any parameter name is not a declared column.

=head2 save

  $record->save;

Persists the current C<row> to disk. On first save:

=over

=item * Assigns a UUID v4 string to C<< row->{id} >> if absent.

=item * Sets C<< row->{createdAt} >> to the current epoch time if absent.

=back

Always updates C<< row->{updatedAt} >> to the current epoch time.

Internally calls C<load> first to ensure the in-memory table is current, then
writes the updated table atomically.

=head2 get

  my $record = $model->get($uuid);

Returns a new model instance for the given UUID, or C<undef> if not found.
The returned object shares the same C<file>, C<log>, and C<table> as the
caller.

=head2 all

  my $records = $model->all;

Returns a hashref clone of every record: C<< { $uuid => \%data, ... } >>.
The returned data is a shallow copy; modifying it does B<not> affect the
model's internal table.

=head2 find

  # With a code reference:
  my $matches = $model->find(sub ($row) { $row->{username} eq 'alice' });

  # With a hash of column => regex pairs (all must match):
  my $matches = $model->find({ username => qr/^a/, disabled => qr/^0$/ });

Searches all records and returns an arrayref of model instances matching the
criteria.

Supports two argument forms:

=over

=item C<CODE> ref

A truth-test coderef receives each record hashref; return true to include.

=item C<HASH> ref

Keys are column names, values are C<qr//> regex objects. A record matches if
B<all> column values match their corresponding regex.

=back

=head2 delete

  $model->delete($uuid);

Removes the record with the given UUID from the table and persists. Returns
true on success, C<undef> if the UUID was not found.

=head1 SUBCLASSING

Subclasses must:

=over

=item 1. Use C<Mojo::Base> to inherit from C<MagicMountain::Model>:

  package MagicMountain::Model::Account;
  use Mojo::Base 'MagicMountain::Model', '-signatures';

=item 2. Override C<columns> to declare the record's fields:

  has columns => sub ($self) {
      my $cols = $self->defaultColumns;
      return [ @$cols, qw(username passwordHash disabled) ];
  };

=item 3. Optionally define convenience accessor methods using C<getCol> /
C<setCol>:

  sub username ($self) { $self->getCol('username') }

=back

See existing subclasses (C<MagicMountain::Model::Account>,
C<MagicMountain::Model::Character>, etc.) for examples.

=head1 DIAGNOSTICS

=over

=item C<Add a path to the state file>

The C<file> attribute was accessed but not provided to the constructor.

=item C<assert: no such column '...' declared on ...>

A call to C<getCol>, C<setCol>, or C<create> referenced a column name not
listed in the subclass's C<columns> attribute.

=item C<JSON DECODE FAILURE: ...>

The JSON file on disk could not be parsed. The error details from
C<Mojo::JSON> are appended.

=item C<assert - unsupport criteria>

C<find> was called with an argument that is neither a CODE nor a HASH
reference.

=back

=head1 CONFIGURATION

The C<file> path is typically set from the application config:

  # In MagicMountain.pm or a startup helper:
  $self->{accountModel} = MagicMountain::Model::Account->new(
      file => $self->config('data_dir') . '/accounts.json',
  );

=head1 DEPENDENCIES

=over

=item L<File::Slurp> - Atomic file read/write

=item L<Mojo::Base> - Object system (Mojolicious)

=item L<Mojo::JSON> - JSON encoding/decoding

=item L<UUID::Tiny> - UUID v4 generation

=item L<Modern::Perl> - Modern Perl language features

=back

=head1 SEE ALSO

L<MagicMountain::Model::Account>, L<MagicMountain::Model::Character>,
L<MagicMountain::Model::Season>, L<MagicMountain::Model::Session>,
L<MagicMountain::Model::AuditLog>

=head1 AUTHOR

Magic Mountain Development Team

=cut
