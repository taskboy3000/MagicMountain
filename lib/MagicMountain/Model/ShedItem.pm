package MagicMountain::Model::ShedItem;
use Mojo::Base 'MagicMountain::Model', '-signatures';

use MagicMountain::ValueTier;

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        char_id artifact_id
        original_value decayed_value condition days_in_shed
        instability stage push_count has_evolved
        behaviors archetypes
        estimated_value_min estimated_value_max
        decay_modifiers
    )];
};

sub value_label ($self) {
    MagicMountain::ValueTier::describe($self->getCol('decayed_value') // $self->getCol('original_value') // 0);
}

1;
