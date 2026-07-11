package MagicMountain::ShedManager;
use Mojo::Base '-base', '-signatures';
use List::Util qw(max);

has app             => sub { die "app is required" };
has log_transcript  => 0;

my %DEFAULT_MODIFIERS = (
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.75,
    fading_multiplier   => 0.40,
    settling_day        => 2,
    fading_day          => 5,
);

sub _fill_modifiers ($mods) {
    $mods //= {};
    for my $key (keys %DEFAULT_MODIFIERS) {
        $mods->{$key} //= $DEFAULT_MODIFIERS{$key};
    }
    return $mods;
}

sub compute_decay ($class, $days_in_shed, $modifiers) {
    my $mods = _fill_modifiers($modifiers);
    my $d    = $days_in_shed;

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

sub apply_decay ($self) {
    my $shed = $self->app->shed;
    $shed->load;

    my $count = 0;
    for my $id (keys %{ $shed->table }) {
        my $item = $shed->get($id) or next;

        my $days     = ($item->getCol('days_in_shed') // 0) + 1;
        my $orig_val = $item->getCol('original_value') // 0;
        my $mods     = $item->getCol('decay_modifiers');

        my ($condition, $mult) = __PACKAGE__->compute_decay($days, $mods);
        my $decayed = int($orig_val * $mult);

        $item->setCol('days_in_shed',       $days);
        $item->setCol('condition',          $condition);
        $item->setCol('decayed_value',      $decayed);
        $item->setCol('estimated_value_min', int($decayed * 0.8));
        $item->setCol('estimated_value_max', int($decayed * 1.2));

        $item->sync_row;

        if ($self->log_transcript) {
            $self->app->transcript->log_event({
                type         => 'decay_tick',
                shed_item_id => $item->getCol('id'),
                char_id      => $item->getCol('char_id'),
                artifact_id  => $item->getCol('artifact_id'),
                days_in_shed => $days,
                condition    => $condition,
                decayed_value => $decayed,
                multiplier   => sprintf('%.4f', $mult),
                narrative    => sprintf("%s day %d: %s (value %d, mult %s).",
                    $item->getCol('artifact_id') // 'unknown',
                    $days, $condition, $decayed, sprintf('%.2f', $mult)),
            });
        }

        $count++;
    }

    $shed->save_table if $count;

    return $count;
}

1;
