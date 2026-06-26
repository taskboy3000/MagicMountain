package MagicMountain::Controller::Home;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use YAML::XS qw(LoadFile);

sub show ($self) {
    my $char = $self->_require_character or return;

    my $ap         = $char->getCol('action_points') // 0;
    my $scrap      = $char->getCol('scrap') // 0;
    my $season     = $self->app->active_season;
    my $season_day = $season ? $season->getCol('day') // 1 : 1;
    my $season_len = $season ? $season->getCol('length') // 30 : 30;

    my $all_shed = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );
    my $shed_count = scalar @$all_shed;

    my $type = $self->_active_activity_type($char);
    my $market_active = ($type && $type eq 'market') ? 1 : 0;

    state $advisories_data = LoadFile($self->app->home . '/content/text/advisories.yml');
    my $advisories = $advisories_data->{advisories} // {};
    my @suggestions = _build_suggestions($ap, $scrap, $shed_count, $season_day, $season_len, $season, $char, $advisories);

    my $crier = $season ? $season->getCol('crier_message') : undef;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my @shed_rows;
        for my $item (@$all_shed) {
            my $aid = $item->getCol('artifact_id');
            push @shed_rows, {
                id         => $item->getCol('id'),
                label      => $aid,
                label_full => $aid,
                icon       => '/images/artifact_' . $aid . '.svg',
                condition  => $item->getCol('condition'),
                value_min  => $item->getCol('estimated_value_min'),
                value_max  => $item->getCol('estimated_value_max'),
                days       => $item->getCol('days_in_shed'),
                behaviors  => $item->getCol('behaviors'),
            };
        }
        $self->stash(
            suggestions   => \@suggestions,
            season_day    => $season_day,
            season_len    => $season_len,
            ap            => $ap,
            scrap         => $scrap,
            shed_count    => $shed_count,
            shed_items    => \@shed_rows,
            market_active => $market_active,
            crier_msg     => $crier,
        );
        return $self->render('home/dashboard', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        suggestions => \@suggestions,
        crier       => $crier,
    });
}

sub _interpolate ($text, $params) {
    $text =~ s!\{(\w+)\}!$params->{$1} // "{$1}"!ge;
    return $text;
}

sub _build_suggestions ($ap, $scrap, $shed_count, $day, $len, $season, $char, $advisories) {
    my @suggestions;

    if ($shed_count > 0 && $ap >= 1) {
        push @suggestions, {
            icon => 'OFFER',
            text => _interpolate($advisories->{shed_available} // '', { shed_count => $shed_count }),
            view => 'bazaar',
        };
    }

    if ($ap >= 2) {
        push @suggestions, {
            icon => 'DRILL',
            text => _interpolate($advisories->{ap_available} // '', { ap => $ap }),
            view => 'prospect',
        };
    }

    if ($shed_count == 0 && $ap < 2) {
        push @suggestions, {
            icon => 'WAIT',
            text => _interpolate($advisories->{idle} // '', { ap => $ap, shed_count => $shed_count }),
            view => undef,
        };
    } elsif ($shed_count > 0 && $ap < 1) {
        push @suggestions, {
            icon => 'CLOCK',
            text => _interpolate($advisories->{no_ap_with_shed} // $advisories->{no_ap} // '', { shed_count => $shed_count }),
            view => undef,
        };
    }

    if ($day > $len - 5) {
        push @suggestions, {
            icon => 'ALERT',
            text => _interpolate($advisories->{season_end} // '', { day => $day, len => $len }),
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
                text => _interpolate($advisories->{faction_hunger} // '', {
                    fs_name => $fs->{name} // ucfirst($fid),
                    fs_days => $fs->{days_since_purchase},
                }),
                view => 'bazaar',
            };
        }
    }

    return @suggestions;
}

1;
