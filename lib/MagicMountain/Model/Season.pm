package MagicMountain::Model::Season;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'length', 'day', 'end_of_day_hour' ];
};

1;