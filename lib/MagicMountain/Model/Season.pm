package MagicMountain::Model::Season;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'label', 'length', 'day', 'end_of_day_hour', 'status', 'faction_state', 'crier_message', 'crier_snapshot' ];
};

1;