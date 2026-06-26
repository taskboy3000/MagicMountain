package MagicMountain::Controller::Market;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) unless $type && $type eq 'market';

    my $activity = $self->app->market->get($char->getCol('pending_activity_id'));
    return $self->rendered(204) unless $activity && $activity->phase ne 'idle';

    my $c = $activity->customer;

    my ($last_sale, $last_message);
    if ($c) {
        $last_sale    = $c->{last_sale};
        $last_message = $c->{last_message};
        $c->{last_sale}    = undef;
        $c->{last_message} = undef;
        $activity->customer($c);
        $activity->save;
    }

    my $pressure_state = $c ? $activity->budget_pressure_state($c)->{state} : undef;

    my $customer_icon;
    if ($c->{faction_id}) {
        my $factions = $self->app->factions_data // [];
        for my $f (@$factions) {
            if ($f->{id} eq $c->{faction_id}) {
                $customer_icon = $f->{icon} ? '/images/' . $f->{icon} : undef;
                last;
            }
        }
    }

    my $portrait_url;
    if ($c->{portrait_id}) {
        my $irritation = $c->{irritation} // 0;
        my $mood = $irritation <= 1 ? 'happy' : ($irritation <= 3 ? 'neutral' : 'mad');
        $portrait_url = '/images/portraits/' . $c->{portrait_id} . '_' . $mood . '.svg';
    }

    my @actions = ({ label => 'Send Away', attrs => { 'data-action-url' => '/market/send_away', 'data-method' => 'POST', id => 'btn-send-away', class => 'mm-btn' } });
    if ($c->{pending_counter}) {
        push @actions, { label => 'Accept Counter-Offer', attrs => { 'data-action-url' => '/market/accept_counter', 'data-method' => 'POST', id => 'btn-accept-counter', class => 'mm-btn mm-btn-primary' } };
        push @actions, { label => 'Stand Pat', attrs => { 'data-action-url' => '/market/stand_pat', 'data-method' => 'POST', id => 'btn-stand-pat', class => 'mm-btn' } };
    }

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            customer_faction_id   => $c->{faction_id},
            customer_faction_name => $c->{faction_name},
            customer_faction_icon => $customer_icon,
            customer_portrait     => $portrait_url,
            customer_disposition  => $c->{disposition} // 'unknown',
            irritation            => $c->{irritation} // 0,
            pressure_state        => $pressure_state,
            pending_counter       => $c->{pending_counter},
            message               => $last_message,
            last_sale             => $last_sale,
            actions               => \@actions,
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
        _self => { actions => \@actions },
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
sub stand_pat      ($self) { $self->_activity_action('stand_pat') }

1;
