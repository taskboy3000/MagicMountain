package MagicMountain::Model::ShedItem;
use Mojo::Base 'MagicMountain::Model', '-signatures';

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

1;
