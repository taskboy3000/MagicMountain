package MagicMountain::Customer;
use Mojo::Base '-base', '-signatures';

has [qw(
    faction_id faction_name faction_icon_url disposition
    irritation spent_so_far soft_budget absolute_budget
    portrait_id
    pending_counter last_message last_sale
    pressure_state pressure_label
)];

sub portrait_url ($self) {
    my $pid = $self->portrait_id or return;
    my $mood = ($self->irritation // 0) <= 1 ? 'happy'
             : ($self->irritation // 0) <= 3 ? 'neutral'
             : 'mad';
    return '/images/portraits/' . $pid . '_' . $mood . '.svg';
}

sub has_pending_counter ($self) {
    return defined $self->pending_counter;
}

sub pending_counter_value ($self) {
    return $self->pending_counter->{value};
}

sub TO_JSON ($self) {
    my $json = {
        faction_id      => $self->faction_id,
        faction_name    => $self->faction_name,
        disposition     => $self->disposition // 'unknown',
        irritation      => $self->irritation,
        pressure_state  => $self->pressure_state,
        ($self->has_pending_counter
            ? (pending_counter => $self->pending_counter)
            : ()),
    };
    return $json;
}

1;
