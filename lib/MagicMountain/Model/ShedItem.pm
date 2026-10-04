package MagicMountain::Model::ShedItem;
use Mojo::Base 'MagicMountain::Model', '-signatures';

use List::Util qw(max);


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

sub current_value ($self) {
    return $self->getCol('decayed_value') // $self->getCol('original_value') // 0;
}

my %DEFAULT_DECAY_MODIFIERS = (
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.75,
    fading_multiplier   => 0.40,
    settling_day        => 2,
    fading_day          => 5,
); 

sub _get_all_decay_modifiers ($self) {
    my $mods = $self->getCol('decay_modifiers') // {};
    for my $k (keys %DEFAULT_DECAY_MODIFIERS) {
        $mods->{$k} //= $DEFAULT_DECAY_MODIFIERS{$k};
    }
    return $mods;
}

sub compute_decay ($self, $days = undef) {
    my $mods = $self->_get_all_decay_modifiers;
    my $d    = $days // $self->getCol('days_in_shed') // 0;

    my ($condition, $mult);

    if ($d < $mods->{settling_day}) {
        $condition = 'fresh';
        $mult      = $mods->{fresh_multiplier};
    } elsif ($d < $mods->{fading_day}) {
        $condition = 'settling';
        my $progress = ($d - $mods->{settling_day})
                     / ($mods->{fading_day} - $mods->{settling_day});
        $mult = $mods->{fresh_multiplier}
              + $progress * ($mods->{settling_multiplier} - $mods->{fresh_multiplier});
    } else {
        $condition = 'fading';
        my $slope = ($mods->{settling_multiplier} - $mods->{fresh_multiplier})
                  / ($mods->{fading_day} - $mods->{settling_day});
        $mult = $mods->{settling_multiplier}
              + ($d - $mods->{fading_day}) * $slope;
        $mult = max($mult, $mods->{fading_multiplier});
    }

    return ($condition, $mult);
}

sub apply_daily_decay ($self) {
    my $days     = ($self->getCol('days_in_shed') // 0) + 1;
    $self->setCol('days_in_shed',       $days);

    my $orig_val = $self->getCol('original_value') // 0;

    my ($condition, $mult) = $self->compute_decay();
    my $decayed = int($orig_val * $mult);

    $self->setCol('condition',          $condition);
    $self->setCol('decayed_value',      $decayed);
    $self->setCol('estimated_value_min', int($decayed * 0.8));
    $self->setCol('estimated_value_max', int($decayed * 1.2));

    $self->save;

    return ($decayed, $mult);    
}

1;
