package MagicMountain::Model::SeasonRecord;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        season_id player_id
        final_score final_scrap rank
        faction_standing_snapshot skills_snapshot
        story_highlights
    )];
};

1;
