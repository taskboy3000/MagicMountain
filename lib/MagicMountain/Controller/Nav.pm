package MagicMountain::Controller::Nav;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::Navigation;

my %SECONDARY = (
    home        => 'factions',
    idle        => 'factions',
    prospecting => 'factions',
    result      => 'factions',
    market      => 'shed',
    factions    => 'leaderboard',
    skills      => 'leaderboard',
    account     => 'leaderboard',
);

my %FRAGMENT_URL = (
    home        => '/home?_format=fragment',
    idle        => '/idle?_format=fragment',
    prospecting => '/prospecting?_format=fragment',
    market      => '/market?_format=fragment',
    result      => '/result?_format=fragment',
    shed        => '/shed?_format=fragment',
    pvp         => '/pvp?_format=fragment',
    factions    => '/factions?_format=fragment',
    skills      => '/skills?_format=fragment',
    leaderboard => '/leaderboard?_format=fragment',
    account     => '/account?_format=fragment',
);

my %TAB_LABEL = (
    home     => 'HOME',
    prospect => 'PROSPECT',
    bazaar   => 'BAZAAR',
    pvp      => 'INTEL',
    skills   => 'CERTS',
);

my %TAB_TO_VIEW = (
    home     => 'home',
    bazaar   => 'market',
    pvp      => 'pvp',
    skills   => 'skills',
);

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    my $ap   = $char->getCol('action_points') // 0;
    my $shed_count = scalar @{ $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    ) };

    my $nav = MagicMountain::Service::Navigation->new(app => $self->app);
    my $primary_tabs = $nav->build_tabs($char, $type, $ap, $shed_count);

    my $view = _resolve_requested_view($self, $primary_tabs);
    if (!$view) {
        $view = $nav->resolve_view($char->getCol('current_view'), $type, $primary_tabs);
    }

    my $current_tab = $nav->tab_id_for($view);
    for my $tab (@$primary_tabs) {
        $tab->{current} = 1 if $tab->{id} eq $current_tab;
    }

    for my $tab (@$primary_tabs) {
        $tab->{label} = $TAB_LABEL{$tab->{id}};
        if ($tab->{id} eq 'bazaar' && $tab->{active} && !$type) {
            $tab->{action_url} = '/market/begin';
        }
        if ($tab->{id} eq 'prospect' && $tab->{active} && !$type) {
            $tab->{action_url} = '/prospecting/begin';
        }
    }

    my $secondary_tabs = $nav->secondary_tabs($char);
    my $secondary      = $SECONDARY{$view} // 'factions';
    my $context        = $self->_context_text($char, $view);

    my $stored = $char->getCol('current_view');
    if (!defined $stored || $stored ne $view) {
        $char->setCol('current_view', $view);
        $char->save;
    }

    $self->render(json => {
        ok                     => 1,
        current_view           => $view,
        primary_fragment_url   => $FRAGMENT_URL{$view},
        secondary_view         => $secondary,
        secondary_fragment_url => $FRAGMENT_URL{$secondary} . '&panel=secondary',
        primary_tabs           => $primary_tabs,
        secondary_tabs         => $secondary_tabs,
        context                => $context,
    });
}

sub toggle ($self) {
    my $char = $self->_require_character or return;
    my $key  = $self->req->json->{key} // '';
    die "invalid toggle key" unless $key eq 'mute';

    my $current = $char->getCol('settings_muted') // 0;
    $char->setCol('settings_muted', $current ? 0 : 1);
    $char->save;

    $self->show;
}

sub _resolve_requested_view ($self, $tabs) {
    my $requested = $self->req->headers->header('X-Nav-View') or return undef;
    my $target = $TAB_TO_VIEW{$requested} or return undef;
    my ($tab) = grep { $_->{id} eq $requested } @$tabs;
    return undef unless $tab && $tab->{active};
    return $target;
}

sub _faction_short_name ($self, $faction_id) {
    my $factions = $self->app->factions_data // [];
    for my $f (@$factions) {
        return $f->{short_name} // $f->{name} if $f->{id} eq $faction_id;
    }
    return $faction_id;
}

sub _context_text ($self, $char, $view) {
    if ($view eq 'home' || $view eq 'idle') {
        my $msg = '';
        my $season = $self->app->active_season;
        if ($season) {
            $msg = $season->getCol('crier_message') || '';
        }
        # Append pressure notice if active target pressures exist.
        if ($self->app->can('pvp_service') && $self->app->config->{pvp_enabled}) {
            $self->app->pressures->load;
            my $aged = $self->app->config->{pvp_pressure_max_age_days};
            my $active = $self->app->pressures->find_active_for_target(
                $char->getCol('id'), undef, $aged);
            if (@$active) {
                my $p = $active->[0];
                $msg .= " \x{7c} " if length $msg;
                $msg .= sprintf "%s pressing your %s lead (%s)",
                    $p->getCol('attacker_id'), $p->getCol('faction_id'),
                    $p->getCol('effect_type');
            }
        }
        return $msg || '';
    }
    if ($view eq 'prospecting') {
        my $id = $char->getCol('pending_activity_id') or return '';
        $self->app->prospecting->load;
        my $act = $self->app->prospecting->get($id) or return '';
        my $a = $act->artifact or return '';
        return sprintf "INSTABILITY %d/%d  \x{7c}  STAGE %s  \x{7c}  VALUE %d",
            $a->{instability} // 0, $a->{max_instability} // 0,
            uc($a->{stage} // ''),
            $a->{value} // 0;
    }
    if ($view eq 'market') {
        my $id = $char->getCol('pending_activity_id') or return '';
        $self->app->market->load;
        my $act = $self->app->market->get($id) or return '';
        my $c = $act->customer or return '';
        my $state = $act->budget_pressure_state($c)->{display};
        my $short = $self->_faction_short_name($c->{faction_id});
        return sprintf "BUYER: %s  \x{7c}  IRRITATION %d  \x{7c}  MOOD: %s",
            $short, $c->{irritation} // 0, $state;
    }
    return '';
}

1;
