package MagicMountain::Model::HallOfFame;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'character_name', 'score', 'season_id' ];
};

1;