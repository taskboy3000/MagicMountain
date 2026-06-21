package MagicMountain::Model::Character;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'name', 'account_id', 'season_id', 'score', 'scrap', 'action_points', 'action_points_max', 'pending_activity_id', 'faction_sales', 'standing', 'current_location', 'skill_prospecting', 'skill_upcycling', 'skill_selling' ];
};

sub validate ($self, $col, $val) {
    if ($col eq 'score' && defined($val) && defined($self->getCol('score'))
        && $val < $self->getCol('score')) {
        die "invariant: score must never decrease";
    }
    if ($col eq 'scrap' && defined($val) && $val < 0) {
        die "invariant: scrap must be non-negative";
    }
    if ($col eq 'action_points' && defined($val)) {
        my $max = $self->getCol('action_points_max') // 15;
        die "invariant: action_points ($val) exceeds max ($max)" if $val > $max;
    }
    if ($col =~ /^skill_/ && defined($val) && ($val < 0 || $val > 3)) {
        die "invariant: $col must be 0-3";
    }
}

1;