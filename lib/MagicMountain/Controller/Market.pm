package MagicMountain::Controller::Market;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) unless $type && $type eq 'market';

    my $activity = $self->app->market->get($char->getCol('pending_activity_id'));
    return $self->rendered(204) unless $activity && $activity->phase ne 'idle';

    my $c = $activity->customer;

    my $pressure_state;
    if ($c) {
        my $pct = ($c->{spent_so_far} // 0) / ($c->{soft_budget} || 1);
        if        ($pct <= 0.50) { $pressure_state = 'mood_comfortable' }
        elsif     ($pct <= 0.80) { $pressure_state = 'mood_interested' }
        elsif     ($pct <= 1.00) { $pressure_state = 'mood_wary' }
        elsif     ($pct <= 1.10) { $pressure_state = 'mood_strained' }
        elsif     ($pct <  1.20) { $pressure_state = 'mood_leaving' }
        else                     { $pressure_state = 'mood_over_absolute' }
    }

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            customer_faction_id   => $c->{faction_id},
            customer_faction_name => $c->{faction_name},
            customer_disposition  => $c->{disposition} // 'unknown',
            irritation            => $c->{irritation} // 0,
            pressure_state        => $pressure_state,
            pending_counter       => $c->{pending_counter},
            message               => $c->{last_message},
            last_sale             => $c->{last_sale},
        );
        return $self->render('market/negotiation', layout => undef);
    }

    $self->render(json => {
        ok     => 1,
        market_visit => {
            customer => {
                faction_id   => $c->{faction_id},
                faction_name => $c->{faction_name},
                disposition  => $c->{disposition} // 'unknown',
                ($c->{pending_counter}
                    ? (pending_counter => $c->{pending_counter})
                    : ()),
            },
            irritation     => $c->{irritation} // 0,
            pressure_state => $pressure_state,
        },
    });
}

sub _activity_action ($self, $action, %params) {
    my $player_id = $self->session('playerId');
    my $season = $self->app->active_season;
    my $season_id = $season ? $season->getCol('id') : undef;

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $m   = $self->app->market;
    my $id  = $char_model->getCol('pending_activity_id');

    my $activity = $id
        ? $m->get($id)
        : $m->create(char_id => $char_model->getCol('id'));

    my $result = $activity->dispatch($char_model, $action, %params);

    $self->_render_action($result, 'market_' . $action);
}

sub begin          ($self) { $self->_activity_action('begin') }
sub offer          ($self) { $self->_activity_action('offer', %{ $self->req->json }) }
sub send_away      ($self) { $self->_activity_action('send_away') }
sub accept_counter ($self) { $self->_activity_action('accept_counter') }

1;
