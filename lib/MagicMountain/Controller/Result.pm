package MagicMountain::Controller::Result;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::CharacterView;

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
    if (!$result) {
        return $self->render(text => '', status => 204);
    }

    my $activity_type = $OUTCOME_ACTIVITY{ $result->{outcome} // '' } // $result->{activity_type};
    my $cv = MagicMountain::Service::CharacterView->new(app => $self->app);
    my $can_continue = $cv->can_continue($char, $activity_type);

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            result       => $result,
            can_continue => $can_continue,
            activity_type => $activity_type,
            continue_url => $self->url_for('result_continue'),
            dismiss_url  => $self->url_for('result_dismiss'),
        );
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

    my $activity_type = $OUTCOME_ACTIVITY{ $result->{outcome} // '' } // $result->{activity_type};
    return $self->render(json => { ok => 0, error => 'cannot continue from this outcome' }, status => 400) unless $activity_type;
    my $cv = MagicMountain::Service::CharacterView->new(app => $self->app);
    return $self->render(json => { ok => 0, error => 'insufficient resources' }, status => 400) unless $cv->can_continue($char, $activity_type);

    $char->nullCol('result');

    if ($activity_type eq 'prospecting') {
        $self->app->prospecting->begin_activity($char);
        $char->setCol('current_view', 'prospecting');
    } else {
        $self->app->market->begin_activity($char);
        $char->setCol('current_view', 'market');
    }

    $char->save;
    $self->render(json => { ok => 1, csrf_token => $self->csrf_token });
}

1;
