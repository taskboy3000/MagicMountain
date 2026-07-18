package MagicMountain::Customer;
use Mojo::Base '-base', '-signatures';

has [qw(
    faction_id faction_name faction_icon_url disposition
    irritation spent_so_far soft_budget absolute_budget
    portrait_id portrait_url
    desired_behaviors
    pending_counter last_message last_sale
    pressure_state pressure_label
    budget_min budget_max
)];

sub has_pending_counter ($self) {
    return defined $self->pending_counter;
}

sub pending_counter_value ($self) {
    return $self->pending_counter->{value};
}

sub TO_JSON ($self) {
    my $json = {
        faction_id        => $self->faction_id,
        faction_name      => $self->faction_name,
        disposition       => $self->disposition // 'unknown',
        irritation        => $self->irritation,
        desired_behaviors => $self->desired_behaviors // [],
        pressure_state    => $self->pressure_state,
        (defined $self->budget_min ? (budget_min => $self->budget_min) : ()),
        (defined $self->budget_max ? (budget_max => $self->budget_max) : ()),
        ($self->has_pending_counter
            ? (pending_counter => $self->pending_counter)
            : ()),
    };
    return $json;
}

1;
