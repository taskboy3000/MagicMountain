package MagicMountain::Model::Activity;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(char_id type phase artifact customer pending_event) ];
};

1;
