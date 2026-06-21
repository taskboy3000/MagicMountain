package MagicMountain::Model::ArtifactDisposition;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        season_id player_id faction_id season_day
        value_awarded artifact_snapshot
        standing_delta influence_delta narrative_hooks
    )];
};

1;
