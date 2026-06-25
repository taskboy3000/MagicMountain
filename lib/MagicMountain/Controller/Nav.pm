package MagicMountain::Controller::Nav;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

my %BASE_TAB = (
    idle => {
        home     => { active => 1, reason => undef },
        prospect => { active => 1, reason => undef },
        bazaar   => { active => 1, reason => undef },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
        account  => { active => 1, reason => undef },
    },
    prospecting => {
        home     => { active => 1, reason => undef },
        prospect => { active => 1, reason => undef },
        bazaar   => { active => 0, reason => 'Finish your current expedition first' },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
        account  => { active => 1, reason => undef },
    },
    market => {
        home     => { active => 1, reason => undef },
        prospect => { active => 0, reason => 'Complete your market visit first' },
        bazaar   => { active => 1, reason => undef },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
        account  => { active => 1, reason => undef },
    },
);

my %SECONDARY = (
    home        => 'factions',
    idle        => 'factions',
    prospecting => 'factions',
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
    shed        => '/shed?_format=fragment',
    factions    => '/factions?_format=fragment',
    skills      => '/skills?_format=fragment',
    account     => '/account?_format=fragment',
);

my %TAB_FRAGMENT_URL = (
    home     => '/home?_format=fragment',
    prospect => '/prospecting?_format=fragment',
    bazaar   => '/market?_format=fragment',
    factions => '/factions?_format=fragment',
    skills   => '/skills?_format=fragment',
    account  => '/account?_format=fragment',
);

my %TAB_LABEL = (
    home     => 'HOME',
    prospect => 'PROSPECT',
    bazaar   => 'BAZAAR',
    factions => 'FACTIONS',
    skills   => 'SKILLS',
    account  => 'ACCOUNT',
);

my %TAB_TO_VIEW = (
    home     => 'home',
    bazaar   => 'market',
    factions => 'factions',
    skills   => 'skills',
    account  => 'account',
);

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    my $ap   = $char->getCol('action_points') // 0;
    my $shed_count = scalar @{ $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    ) };

    my $tabs = _build_tabs($type, $ap, $shed_count);

    # Determine current view: header request > stored view > activity default
    my $view;
    my $requested = $self->req->headers->header('X-Nav-View');
    if ($requested) {
        my $target = $TAB_TO_VIEW{$requested};
        if ($target) {
            my ($tab) = grep { $_->{id} eq $requested } @$tabs;
            if ($tab && $tab->{active}) {
                $view = $target;
                $char->setCol('current_view', $view);
                $char->save;
            }
        }
    }
    if (!$view) {
        $view = $char->getCol('current_view') || $type || 'home';
        # Stored activity view with no activity → go home
        if (($view eq 'prospecting' || $view eq 'market') && !$type) {
            $view = 'home';
        }
        # Active activity overrides stored view
        if ($type && $view ne $type) {
            $view = $type;
        }
        # View maps to inactive tab → fall back
        if (!$type) {
            my ($tab) = grep { $_->{id} eq _tab_id_for($view) } @$tabs;
            $view = 'home' unless $tab && $tab->{active};
        }
    }

    # Mark current tab
    my $current_tab = _tab_id_for($view);
    for my $tab (@$tabs) {
        $tab->{current} = 1 if $tab->{id} eq $current_tab;
    }

    my $secondary = $SECONDARY{$view} // 'factions';
    my $context = $self->_context_text($char, $view);

    # Sync stored view if it changed
    my $stored = $char->getCol('current_view');
    if (!defined $stored || $stored ne $view) {
        $char->setCol('current_view', $view);
        $char->save;
    }

    my $secondary_url = $FRAGMENT_URL{$secondary} . '&panel=secondary';

    $self->render(json => {
        current_view           => $view,
        primary_fragment_url   => $FRAGMENT_URL{$view},
        secondary_view         => $secondary,
        secondary_fragment_url => $secondary_url,
        tabs                   => $tabs,
        context                => $context,
    });
}

sub _tab_id_for ($view) {
    my %map = (
        home        => 'home',
        idle        => 'prospect',
        prospecting => 'prospect',
        market      => 'bazaar',
        factions    => 'factions',
        skills      => 'skills',
        account     => 'account',
    );
    return $map{$view} || 'home';
}

sub _build_tabs ($type, $ap, $shed_count) {
    my $base     = $BASE_TAB{$type // 'idle'} // $BASE_TAB{idle};
    my @tab_ids  = qw(home prospect bazaar factions skills account);
    my @tabs;
    for my $id (@tab_ids) {
        my $entry = { %{ $base->{$id} } };
        if ($id eq 'bazaar' && $entry->{active}) {
            if ($ap < 1) {
                $entry->{active} = 0; $entry->{reason} = 'No AP remaining';
            } elsif ($shed_count < 1) {
                $entry->{active} = 0; $entry->{reason} = 'No artifacts in shed';
            } elsif (!$type) {
                $entry->{action_url} = '/market/begin';
            }
        }
        if ($id eq 'prospect' && $entry->{active} && !$type) {
            if ($ap < 2) {
                $entry->{active} = 0; $entry->{reason} = 'Not enough AP (2 required)';
            } else {
                $entry->{action_url} = '/prospecting/begin';
            }
        }
        push @tabs, {
            id            => $id,
            label         => $TAB_LABEL{$id},
            active        => $entry->{active},
            reason        => $entry->{reason},
            fragment_url  => $TAB_FRAGMENT_URL{$id},
            ($entry->{action_url} ? (action_url => $entry->{action_url}) : ()),
        };
    }
    return \@tabs;
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
        my $budget = $c->{soft_budget} || 1;
        my $pct = ($c->{spent_so_far} // 0) / $budget;
        my $state;
        if    ($pct <= 0.50) { $state = 'COMFORTABLE' }
        elsif ($pct <= 0.80) { $state = 'INTERESTED' }
        elsif ($pct <= 1.00) { $state = 'WARY' }
        elsif ($pct <  1.20) { $state = 'STRAINED' }
        else                 { $state = 'OVER LIMIT' }
        my $short = $self->_faction_short_name($c->{faction_id});
        return sprintf "BUYER: %s  \x{7c}  IRRITATION %d  \x{7c}  MOOD: %s",
            $short, $c->{irritation} // 0, $state;
    }
    return '';
}

1;
