package MagicMountain::Controller::Nav;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::Navigation;

my %SECONDARY = (
    home          => 'factions',
    idle          => 'factions',
    prospecting   => 'factions',
    result        => 'factions',
    market        => 'shed',
    pawn          => 'shed',
    factions      => 'leaderboard',
    skills        => 'leaderboard',
    account       => 'leaderboard',
);

my %FRAGMENT_URL = (
    home        => sub ($c) { $c->url_for('home')->query(_format => 'fragment') },
    idle        => sub ($c) { $c->url_for('idle')->query(_format => 'fragment') },
    prospecting => sub ($c) { $c->url_for('prospecting_show')->query(_format => 'fragment') },
    market      => sub ($c) { $c->url_for('market_show')->query(_format => 'fragment') },
    pawn        => sub ($c) { $c->url_for('pawn_show')->query(_format => 'fragment') },
    result      => sub ($c) { $c->url_for('result_show')->query(_format => 'fragment') },
    shed        => sub ($c) { $c->url_for('shed')->query(_format => 'fragment') },
    pvp         => sub ($c) { $c->url_for('pvp_show')->query(_format => 'fragment') },
    factions    => sub ($c) { $c->url_for('factions')->query(_format => 'fragment') },
    skills      => sub ($c) { $c->url_for('skills')->query(_format => 'fragment') },
    leaderboard => sub ($c) { $c->url_for('leaderboard')->query(_format => 'fragment') },
    account     => sub ($c) { $c->url_for('account')->query(_format => 'fragment') },
);

my %TAB_LABEL = (
    home     => 'HOME',
    prospect => 'PROSPECT',
    bazaar   => 'BAZAAR',
    pawn     => 'PAWN',
    pvp      => 'INTEL',
    skills   => 'CERTS',
);

my %TAB_TO_VIEW = (
    home     => 'home',
    bazaar   => 'market',
    pawn     => 'pawn',
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
    my $base     = $nav->base_tab_state($type);
    my $overrides = {};
    if ($base->{bazaar}{active}) {
        if ($ap < 1) {
            $overrides->{bazaar} = { active => 0, reason => 'No AP remaining' };
        } elsif ($shed_count < 1) {
            $overrides->{bazaar} = { active => 0, reason => 'No artifacts in shed' };
        }
    }
    if ($base->{prospect}{active}) {
        if ($ap < 2) {
            $overrides->{prospect} = { active => 0, reason => 'Not enough AP (2 required)' };
        }
    }
    if ($base->{pawn}{active}) {
        my $calc = $self->app->pawn_calculator;
        if (!$calc->has_banned_items($char)) {
            $overrides->{pawn} = { active => 0, reason => 'No restricted items' };
        }
    }
    my $primary_tabs = $nav->build_tabs($char, $type, $overrides);

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
            $tab->{action_url} = $self->url_for('market_begin');
        }
        if ($tab->{id} eq 'prospect' && $tab->{active} && !$type) {
            $tab->{action_url} = $self->url_for('prospecting_begin');
        }
        if ($tab->{id} eq 'pawn' && $tab->{active} && !$type) {
            $tab->{action_url} = $self->url_for('pawn_show');
        }
    }

    my $secondary_tabs = $nav->secondary_tabs($char, {
        factions_url     => $self->url_for('factions')->query(_format => 'fragment'),
        account_url      => $self->url_for('account')->query(_format => 'fragment'),
        orientation_url  => $self->url_for('orientation')->query(_format => 'fragment'),
        toggle_url       => $self->url_for('nav_toggle'),
    });
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
        primary_fragment_url   => $FRAGMENT_URL{$view}->($self),
        secondary_view         => $secondary,
        secondary_fragment_url => $FRAGMENT_URL{$secondary}->($self) . '&panel=secondary',
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
    my $requested = $self->req->headers->header('X-Nav-View') or return;
    my $target = $TAB_TO_VIEW{$requested} or return;
    my ($tab) = grep { $_->{id} eq $requested } @$tabs;
    return unless $tab && $tab->{active};
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
    if ($view eq 'pawn') {
        my $id = $char->getCol('pending_activity_id') or return '';
        $self->app->pawn->load;
        my $act = $self->app->pawn->get($id) or return '';
        my $c = $act->customer or return '';
        my $seizure_pct = $c->{outcome} ? 0 : ($c->{seizure_chance} // 0) * 100;
        return sprintf "BROKER  \x{7c}  %s  \x{7c}  SEIZURE RISK %.0f%%",
            $c->{outcome} ? 'RESULT' : 'AWAITING',
            $seizure_pct;
    }
    return '';
}

1;
