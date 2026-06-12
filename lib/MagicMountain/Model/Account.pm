package MagicMountain::Model::Account;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'username', 'password', 'disabled' ];
};

sub find_by_username ($self, $username) {
    $self->load;
    for my $id (keys %{$self->table}) {
        my $row = $self->table->{$id};
        if (($row->{username} // '') eq $username) {
            return $self->new(
                file  => $self->file,
                log   => $self->log,
                table => $self->table,
                row   => { %{ $row } },
            );
        }
    }
    return;
}

1;