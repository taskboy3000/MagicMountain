package MagicMountain::Model::Season;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(label length day end_of_day_hour status faction_state faction_climate crier_message crier_snapshot last_maintenance daily_modifiers personal_event_counts global_event_text) ];
};

sub daily_modifier ($self, $key, $default) {
    my $mods = $self->getCol('daily_modifiers') // {};
    return exists $mods->{$key} ? $mods->{$key} : $default;
}

sub faction_climate ($self) {
    return $self->getCol('faction_climate') // {};
}

1;