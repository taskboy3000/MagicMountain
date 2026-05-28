package MagicMountain::Model;
# This is a base class for all the objects that need persisting


use File::Slurp qw(read_file write_file);
use Modern::Perl;
use Mojo::Base '-base', '-signatures';
use Mojo::JSON ('encode_json', 'decode_json');
use UUID::Tiny (':std');

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
has _last_mtime => sub ($self) { 0 };

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
        return $self->row->{$columnName} = $optionalValue
    }
    die ("assert: no such column '$columnName' declared on " . ref $self);
}

sub hasCol ($self, $columnName) {
    return grep {$_ eq $columnName} @{$self->columns};
}

# Load all data from $self->file
sub load ($self) {
    my $mtime = (stat($self->file))[9] // 0;
    return 1 if $mtime && $mtime == $self->_last_mtime;

    if (-e $self->file) {
        my $content = read_file($self->file);
        my $data;
        eval {
            $data = decode_json($content);
            1;
        } or do {
            die("JSON DECODE FAILURE: $@");
        };
        %{ $self->table } = %{ $data };
        $self->_last_mtime($mtime);
    }

    return 1;
}

# Only saves the table in its current form
sub _saveTable ($self) {
    my $json = encode_json($self->table);
    my $tmpFile = $self->file . "$$.tmp";
    write_file($tmpFile, $json);
    rename $tmpFile, $self->file;
    $self->_last_mtime((stat($self->file))[9] // 0);
    return 1;
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
    return $new;
}

# Persist this one $self->data record to $self->file
sub save ($self) {
    $self->load; # important.  Get the whole table before altering
    if (!$self->row->{id}) {
        $self->row->{id} = create_uuid_as_string();
    }

    if (!$self->row->{createdAt}) {
        $self->row->{createdAt} = time();
    }

    $self->row->{updatedAt} = time();

    # we are updating the table
    $self->table->{$self->row->{id}} = $self->row;
    return $self->_saveTable;
}




sub get ($self, $id) {
    $self->load;
    if ($id && $self->table->{$id}) {
        return $self->new(
            file => $self->file,
            log => $self->log,
            table => $self->table,
            row => { %{ $self->table->{$id} }}
        );
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


sub delete ($self, $id) {
    $self->load;

    if ($self->table->{$id}) {
        delete $self->table->{$id};
        return $self->_saveTable;
    }
    return;
}

1;