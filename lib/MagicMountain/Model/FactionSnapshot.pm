package MagicMountain::Model::FactionSnapshot;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'season_id', 'day', 'faction_id', 'influence',
             'artifacts_received', 'intake_by_trait' ];
};

1;
