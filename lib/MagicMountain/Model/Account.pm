package MagicMountain::Model::Account;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'username', 'token_hash', 'remember_token_hash', 'recovery_code_hash', 'banned' ];
};

sub create ($self, %params) {
    $params{banned} //= 0;
    return $self->SUPER::create(%params);
}

sub find_by_username ($self, $username) {
    my $found = $self->find(sub { $_[0]->{username} eq $username });
    return $found->[0];
}

1;
