package MagicMountain::Model::Account;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'username', 'password', 'disabled' ];
};

sub find_by_username ($self, $username) {
    my $found = $self->find(sub { $_[0]->{username} eq $username });
    return $found->[0];
}

1;