package MagicMountain::Controller::Result;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

my %OUTCOME_ACTIVITY = (
    breakthrough => 'prospecting',
    collapse     => 'prospecting',
    stopped      => 'prospecting',
    sold         => 'market',
    sold_more    => 'market',
    sent_away    => 'market',
    customer_left    => 'market',
    over_budget  => 'market',
);

sub show ($self) {
    my $char = $self->_require_character or return;
    my $result = $char->getCol('result');
    unless ($result) {
        return $self->render(text => '', status => 204);
    }

    my $activity_type = $OUTCOME_ACTIVITY{ $result->{outcome} // '' };
    my $can_continue = $self->_can_continue($char, $activity_type);

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(result => $result, can_continue => $can_continue, activity_type => $activity_type);
        return $self->render('result/show', layout => undef);
    }
    $self->render(json => { ok => 1, result => $result, can_continue => $can_continue });
}

sub dismiss ($self) {
    my $char = $self->_require_character or return;
    $char->nullCol('result');
    $char->setCol('current_view', 'home');
    $char->save;
    $self->render(json => { ok => 1, csrf_token => $self->csrf_token });
}

sub do_continue ($self) {
    my $char = $self->_require_character or return;
    my $result = $char->getCol('result');
    return $self->render(json => { ok => 0, error => 'no result' }, status => 400) unless $result;

    my $activity_type = $OUTCOME_ACTIVITY{ $result->{outcome} // '' };
    return $self->render(json => { ok => 0, error => 'cannot continue from this outcome' }, status => 400) unless $activity_type;
    return $self->render(json => { ok => 0, error => 'insufficient resources' }, status => 400) unless $self->_can_continue($char, $activity_type);

    $char->nullCol('result');

    if ($activity_type eq 'prospecting') {
        my $activity = $self->app->prospecting->create(char_id => $char->getCol('id'));
        $activity->dispatch($char, 'begin');
        $char->setCol('current_view', 'prospecting');
    } else {
        my $activity = $self->app->market->create(char_id => $char->getCol('id'));
        $activity->dispatch($char, 'begin');
        $char->setCol('current_view', 'market');
    }

    $char->save;
    $self->render(json => { ok => 1, csrf_token => $self->csrf_token });
}

sub _can_continue ($self, $char, $activity_type) {
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
