package MagicMountain::Model::Character;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'name', 'account_id', 'season_id', 'score', 'scrap', 'action_points', 'action_points_max', 'pending_activity_id', 'faction_sales', 'standing', 'faction_snubs', 'snub_day', 'current_location', 'current_view', 'result', 'skill_prospecting', 'skill_upcycling', 'skill_selling', 'loyalty_visits_since', 'is_bot', 'bot_profile_id', 'seen_orientation', 'settings_muted' ];
};

has app => undef;

sub create ($self, %params) {
    $params{loyalty_visits_since} //= 0;
    $params{faction_snubs}        //= {};
    $params{seen_orientation}     //= 0;
    $params{settings_muted}       //= 0;
    my $obj = $self->SUPER::create(%params);
    $obj->app($self->app);
    return $obj;
}

sub get ($self, $id) {
    my $obj = $self->SUPER::get($id);
    $obj->app($self->app) if $obj;
    return $obj;
}

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
    if ($col =~ /^skill_/ && defined($val) && ($val < 0 || $val > 4)) {
        die "invariant: $col must be 0-4";
    }
}

sub add_scrap ($self, $n) {
    my $scrap = $self->getCol('scrap') + $n;
    $scrap = 0 if $scrap < 0;
    $self->setCol('scrap', $scrap);
}

sub add_score ($self, $n) {
    my $score = $self->getCol('score') + $n;
    $self->setCol('score', $score);
}

sub prospecting_view ($self) {
    my $id = $self->getCol('pending_activity_id') or return undef;
    $self->app->prospecting->load;
    my $type = $self->app->prospecting->table->{$id}{type} // '';
    return undef unless $type eq 'prospecting';

    my $activity = $self->app->prospecting->get($id);
    return undef unless $activity && $activity->phase ne 'idle';

    my $a = $activity->artifact;
    return {
        id     => $a->{id},
        stage  => $a->{stage},
        value  => $a->{value},
        signal => $a->{signal},
        intro  => $a->{intro},
    };
}

sub market_view ($self) {
    my $id = $self->getCol('pending_activity_id') or return undef;
    $self->app->prospecting->load;
    my $type = $self->app->prospecting->table->{$id}{type} // '';
    return undef unless $type eq 'market_visit';

    my $activity = $self->app->market->get($id);
    return undef unless $activity && $activity->phase ne 'idle';

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

sub shed_items ($self) {
    my $char_id = $self->getCol('id') or return [];
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

sub player_skills ($self) {
    my $skills = $self->app->skills_data;
    for my $s (@$skills) {
        $s->{current_level} = $self->getCol('skill_' . $s->{id}) // 0;
    }
    return $skills;
}

1;