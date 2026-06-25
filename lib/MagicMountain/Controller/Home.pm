package MagicMountain::Controller::Home;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;

    my $ap         = $char->getCol('action_points') // 0;
    my $scrap      = $char->getCol('scrap') // 0;
    my $season     = $self->app->active_season;
    my $season_day = $season ? $season->getCol('day') // 1 : 1;
    my $season_len = $season ? $season->getCol('length') // 30 : 30;

    my $shed_count = scalar @{ $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    ) };

    my @suggestions = _build_suggestions($ap, $scrap, $shed_count, $season_day, $season_len, $season, $char);

    my $crier = $season ? $season->getCol('crier_message') : undef;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            suggestions  => \@suggestions,
            season_day   => $season_day,
            season_len   => $season_len,
            ap           => $ap,
            scrap        => $scrap,
            shed_count   => $shed_count,
            crier_msg    => $crier,
        );
        return $self->render('home/dashboard', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        suggestions => \@suggestions,
        crier       => $crier,
    });
}

sub _build_suggestions ($ap, $scrap, $shed_count, $day, $len, $season, $char) {
    my @suggestions;

    if ($shed_count > 0 && $ap >= 1) {
        push @suggestions, {
            icon => 'OFFER',
            text => "You have $shed_count artifact" . ($shed_count > 1 ? 's' : '')
                . " in the shed ready to sell. Visit the Bazaar.",
            view => 'bazaar',
        };
    }

    if ($ap >= 2) {
        push @suggestions, {
            icon => 'DRILL',
            text => "You have $ap AP remaining — the mountain is calling. Begin a prospecting expedition.",
            view => 'prospect',
        };
    }

    if ($shed_count == 0 && $ap < 2) {
        push @suggestions, {
            icon => 'WAIT',
            text => "Not enough AP to prospect and nothing in the shed. AP refreshes at the next day cycle.",
            view => undef,
        };
    } elsif ($shed_count > 0 && $ap < 1) {
        push @suggestions, {
            icon => 'CLOCK',
            text => "No AP remaining, but you have $shed_count artifact"
                . ($shed_count > 1 ? 's' : '') . " in the shed. Return after the next maintenance window.",
            view => undef,
        };
    }

    if ($day > $len - 5) {
        push @suggestions, {
            icon => 'ALERT',
            text => "Day $day of $len — the season is winding down. Sell your artifacts before it ends!",
            view => 'shed',
        };
    }

    if ($season && $shed_count > 0) {
        my $faction_state = $season->getCol('faction_state') // {};
        my $standing      = $char->getCol('standing') // {};
        for my $fid (keys %$faction_state) {
            my $fs = $faction_state->{$fid};
            next unless $fs->{days_since_purchase} && $fs->{days_since_purchase} >= 3;
            push @suggestions, {
                icon => 'PREMIUM',
                text => "The " . ($fs->{name} // ucfirst($fid))
                    . " hasn't bought in $fs->{days_since_purchase} days — they'll pay a premium!",
                view => 'bazaar',
            };
        }
    }

    return @suggestions;
}

1;
