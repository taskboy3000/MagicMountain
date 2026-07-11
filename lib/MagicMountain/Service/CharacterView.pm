package MagicMountain::Service::CharacterView;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub prospecting_view ($self, $char) {
    my $id = $char->getCol('pending_activity_id') or return;
    $self->app->prospecting->load;
    my $type = $self->app->prospecting->table->{$id}{type} // '';
    return unless $type eq 'prospecting';

    my $activity = $self->app->prospecting->get($id);
    return unless $activity && $activity->phase ne 'idle';

    my $a = $activity->artifact;
    return {
        id     => $a->{id},
        stage  => $a->{stage},
        value  => $a->{value},
        signal => $a->{signal},
        intro  => $a->{intro},
    };
}

sub market_view ($self, $char) {
    my $id = $char->getCol('pending_activity_id') or return;
    $self->app->prospecting->load;
    my $type = $self->app->prospecting->table->{$id}{type} // '';
    return unless $type eq 'market_visit';

    my $activity = $self->app->market->get($id);
    return unless $activity && $activity->phase ne 'idle';

    my $c = $activity->customer;
    my $pressure_state = $c ? $activity->budget_pressure_state($c)->{state} : undef;

    return {
        customer => {
            faction_id      => $c->{faction_id},
            faction_name    => $c->{faction_name},
            disposition     => $c->{disposition} // 'unknown',
            ($c->{pending_counter}
                ? (pending_counter => $c->{pending_counter})
                : ()),
        },
        irritation     => $c->{irritation} // 0,
        pressure_state => $pressure_state,
    };
}

sub shed_items ($self, $char) {
    my $char_id = $char->getCol('id') or return [];
    my $items = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char_id }
    );
    my @result;
    for my $item (@$items) {
        push @result, {
            id                   => $item->getCol('id'),
            artifact_id          => $item->getCol('artifact_id'),
            condition            => $item->getCol('condition'),
            days_in_shed         => $item->getCol('days_in_shed'),
            estimated_value_min  => $item->getCol('estimated_value_min'),
            estimated_value_max  => $item->getCol('estimated_value_max'),
        };
    }
    return \@result;
}

sub player_skills ($self, $char) {
    my $skills = $self->app->skills_data;
    for my $s (@$skills) {
        $s->{current_level} = $char->getCol('skill_' . $s->{id}) // 0;
    }
    return $skills;
}

sub can_continue ($self, $char, $activity_type) {
    return 0 unless $activity_type;
    my $ap = $char->getCol('action_points') // 0;
    if ($activity_type eq 'prospecting') {
        return $ap >= 2;
    }
    if ($activity_type eq 'market') {
        return 0 if $ap < 1;
        my $shed_count = scalar @{ $self->app->shed->find(
            sub { $_[0]->{char_id} eq $char->getCol('id') }
        ) };
        return $shed_count > 0;
    }
    return 0;
}

1;
