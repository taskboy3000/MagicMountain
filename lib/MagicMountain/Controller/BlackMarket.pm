package MagicMountain::Controller::BlackMarket;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->render(status => 204, text => '') unless $type && $type eq 'black_market';

    my $activity = $self->app->black_market->get($char->getCol('pending_activity_id'));
    return $self->render(status => 204, text => '') unless $activity && $activity->phase ne 'idle';

    my $deal = $activity->customer;
    my $accept_url  = $self->url_for('black_market_accept');
    my $withdraw_url = $self->url_for('black_market_withdraw');

    my @actions = (
        { label => 'Accept', attrs => { 'data-action-url' => $accept_url, 'data-method' => 'POST', id => 'btn-bm-accept', class => 'mm-btn mm-btn-primary' } },
        { label => 'Withdraw', attrs => { 'data-action-url' => $withdraw_url, 'data-method' => 'POST', id => 'btn-bm-withdraw', class => 'mm-btn' } },
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            deal    => $deal,
            actions => \@actions,
        );
        return $self->render('black_market/broker', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        black_market => {
            offer_value    => $deal->{offer_value},
            seizure_chance => $deal->{seizure_chance},
            premium_mult   => $deal->{premium_mult},
            artifact_id    => $deal->{artifact_id},
            message        => $deal->{arrival_text},
        },
        _self => { actions => \@actions },
    });
}

sub _activity_action ($self, $action, %params) {
    my $char = $self->_require_character or return;

    my $bm  = $self->app->black_market;
    my $id  = $char->getCol('pending_activity_id');

    if (!$id) {
        return $self->render(json => { ok => 0, error => 'No active black market session' }, status => 400);
    }

    my $activity = $bm->get($id);

    my $result = eval { $activity->dispatch($char, $action, %params) };
    if (my $err = $@) {
        return $self->render(json => { ok => 0, error => $err }, status => 409);
    }

    $self->_render_action($result, 'black_market_' . $action);
}

sub accept   ($self) { $self->_activity_action('accept') }
sub withdraw ($self) { $self->_activity_action('withdraw') }

1;
