package MagicMountain::Model::Pressure;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        attacker_id target_id faction_id effect_type
        target_consumed attacker_consumed
    )];
};

sub create ($self, %params) {
    $params{target_consumed}   //= 0;
    $params{attacker_consumed} //= 0;
    return $self->SUPER::create(%params);
}

sub _consumed_col ($self, $age_key) {
    return $age_key eq 'target_id' ? 'target_consumed' : 'attacker_consumed';
}

sub _find_active ($self, $char_id, $faction_id, $age_key, $max_age_days = undef) {
    my $now    = CORE::time;
    my $cutoff = defined $max_age_days ? $now - ($max_age_days * 86400) : 0;
    my $faction_allowed = !defined $faction_id;

    my @matches = grep {
        $_->{$age_key}              eq $char_id
        && ($faction_allowed       || $_->{faction_id} eq $faction_id)
        && !$_->{ $self->_consumed_col($age_key) }
        && ($_->{createdAt} // 0)  >= $cutoff
    } values %{$self->table};

    {
        # Purge stale unconsumed rows (past the max_age_days cutoff) AND
        # fully-consumed rows (both consumed flags set) regardless of age.
        # This keeps pressures.json clean without a maintenance hook.
        my @purge = grep {
            ($_->{$age_key} eq $char_id)
            && ($faction_allowed || $_->{faction_id} eq $faction_id)
            && (
               # Stale: still active on this side but too old
               (defined $max_age_days
                && !$_->{ $self->_consumed_col($age_key) }
                && ($_->{createdAt} // 0) < $cutoff)
               ||
               # Fully consumed both sides — clean up regardless of age
               ($_->{target_consumed} && $_->{attacker_consumed})
            )
        } values %{$self->table};
        if (@purge) {
            delete $self->table->{$_->{id}} for @purge; # ok: model violation for performance
            $self->_saveTable;
        }
    }

    return [ map { $self->get($_->{id}) } @matches ];
}

sub find_active_for_target ($self, $char_id, $faction_id, $max_age_days = undef) {
    return $self->_find_active($char_id, $faction_id, 'target_id', $max_age_days);
}

sub find_active_for_attacker ($self, $char_id, $faction_id, $max_age_days = undef) {
    return $self->_find_active($char_id, $faction_id, 'attacker_id', $max_age_days);
}

sub count_active_on ($self, $char_id, $faction_id, $max_age_days = undef) {
    return scalar @{ $self->find_active_for_target($char_id, $faction_id, $max_age_days) };
}

1;
