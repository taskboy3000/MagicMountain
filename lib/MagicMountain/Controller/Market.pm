package MagicMountain::Controller::Market;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Customer;

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) unless $type && $type eq 'market';

    my $activity = $self->app->market->get($char->getCol('pending_activity_id'));
    return $self->rendered(204) unless $activity && $activity->phase ne 'idle';

    my $c = $activity->customer;

    my $pressure = $c ? $activity->budget_pressure_state($c) : undef;
    my $faction_icon_url;
    if ($c->{faction_id}) {
        my $factions = $self->app->factions_data // [];
        for my $f (@$factions) {
            if ($f->{id} eq $c->{faction_id}) {
                $faction_icon_url = $f->{icon} ? $self->url_for('/images') . '/' . $f->{icon} : undef;
                last;
            }
        }
    }

    my ($last_sale, $last_message);
    if ($c) {
        $last_sale    = $c->{last_sale};
        $last_message = $c->{last_message};
        $c->{last_sale}    = undef;
        $c->{last_message} = undef;
        $activity->customer($c);
        $activity->save;
    }

    my $sell = $char->getCol('skill_selling') // 0;
    my $portrait_url;
    if ($c && $c->{portrait_id}) {
        my $mood = ($c->{irritation} // 0) <= 1 ? 'happy'
                 : ($c->{irritation} // 0) <= 3 ? 'neutral'
                 : 'mad';
        $portrait_url = $self->url_for('/images') . '/portraits/' . $c->{portrait_id} . '_' . $mood . '.svg';
    }
    my $customer = $c ? MagicMountain::Customer->new({
        %$c,
        portrait_url     => $portrait_url,
        faction_icon_url => $faction_icon_url,
        pressure_state   => $pressure ? $pressure->{state}   : undef,
        pressure_label   => $pressure ? $pressure->{display} : undef,
        last_sale        => $last_sale,
        last_message     => $last_message,
        ($sell >= 3 ? (
            budget_min => $c->{soft_budget},
            budget_max => $c->{absolute_budget},
        ) : ()),
    }) : undef;

    my $send_away_url     = $self->url_for('market_send_away');
    my $accept_counter_url = $self->url_for('market_accept_counter');
    my $stand_pat_url      = $self->url_for('market_stand_pat');
    my @actions = ({ label => 'Send Away', attrs => { 'data-action-url' => $send_away_url, 'data-method' => 'POST', id => 'btn-send-away', class => 'mm-btn' } });
    if ($c && $c->{pending_counter}) {
        push @actions, { label => 'Accept Counter-Offer', attrs => { 'data-action-url' => $accept_counter_url, 'data-method' => 'POST', id => 'btn-accept-counter', class => 'mm-btn mm-btn-primary' } };
        push @actions, { label => 'Stand Pat', attrs => { 'data-action-url' => $stand_pat_url, 'data-method' => 'POST', id => 'btn-stand-pat', class => 'mm-btn' } };
    }

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(customer => $customer, actions => \@actions);
        return $self->render('market/negotiation', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        market_visit => $customer,
        _self       => { actions => \@actions },
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

    if (!$id) {
        if ($action ne 'begin') {
            return $self->render(json => { ok => 0, error => 'No active market visit' }, status => 400);
        }
    }

    if (!$id && $action ne 'begin') {
        return $self->render(json => { ok => 0, error => 'No active market visit' }, status => 400);
    }

    my $result = eval {
        if ($action eq 'begin') {
            $m->begin_activity($char_model, %params);
        } else {
            $m->get($id)->dispatch($char_model, $action, %params);
        }
    };
    if (my $err = $@) {
        return $self->render(json => { ok => 0, error => $err }, status => 409);
    }

    $self->_render_action($result, 'market_' . $action);
}

sub begin          ($self) { $self->_activity_action('begin') }
sub offer          ($self) { $self->_activity_action('offer', %{ $self->req->json }) }
sub send_away      ($self) { $self->_activity_action('send_away') }
sub accept_counter ($self) { $self->_activity_action('accept_counter') }
sub stand_pat      ($self) { $self->_activity_action('stand_pat') }

1;
