package MagicMountain::Service::Suggestion;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub build ($self, $char, $season, $advisories, $shed_count) {
    my $ap    = $char->getCol('action_points') // 0;
    my $scrap = $char->getCol('scrap') // 0;
    my $day   = $season ? $season->getCol('day') // 1     : 1;
    my $len   = $season ? $season->getCol('length') // 30  : 30;

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

    return \@suggestions;
}

sub _interpolate ($text, $params) {
    $text =~ s!\{(\w+)\}!$params->{$1} // "{$1}"!ge;
    return $text;
}

1;
