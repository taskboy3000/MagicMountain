package MagicMountain::Service::Suggestion;
use Mojo::Base '-base', '-signatures';

use constant FACTION_DESPERATION_DAYS => 3;

has app => sub { die "app is required" };

sub _prospect_ap_cost ($self, $season) {
    return $season ? $season->daily_modifier('prospect_ap_cost', 2) : 2;
}

sub build ($self, $char, $season, $advisories, $all_shed) {
    my $ap         = $char->getCol('action_points') // 0;
    my $scrap      = $char->getCol('scrap') // 0;
    my $day        = $season ? $season->getCol('day') // 1     : 1;
    my $len        = $season ? $season->getCol('length') // 30  : 30;
    my $shed_count = scalar @$all_shed;
    my $prospect_cost = $self->_prospect_ap_cost($season);

    my @suggestions;

    if ($shed_count > 0 && $ap >= 1) {
        push @suggestions, {
            icon => 'OFFER',
            text => _interpolate($advisories->{shed_available} // '', { shed_count => $shed_count }),
            view => 'bazaar',
        };
    }

    if ($ap >= $prospect_cost) {
        push @suggestions, {
            icon => 'DRILL',
            text => _interpolate($advisories->{ap_available} // '', { ap => $ap }),
            view => 'prospect',
        };
    }

    if ($season && $ap >= $prospect_cost) {
        my $climate = $season->getCol('faction_climate') // {};
        if ($climate->{has_meaningful_finds}) {
            push @suggestions, {
                icon => 'DRILL',
                text => _interpolate($advisories->{climate_finds} // '', {
                    finds_summary => $climate->{finds_summary},
                }),
                view => 'prospect',
            };
        }
    }

    if ($shed_count == 0 && $ap < $prospect_cost) {
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
            next unless $fs->{days_since_purchase} && $fs->{days_since_purchase} >= FACTION_DESPERATION_DAYS;
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

    if ($season && $shed_count > 0) {
        my $climate = $season->getCol('faction_climate') // {};
        my $biases  = $climate->{market}{buyer_trait_biases} // {};
        if (keys %$biases) {
            my $found;
            my %wanted = map { $_ => 1 } keys %$biases;
            ITEM: for my $shed (@$all_shed) {
                for my $b (@{ $shed->getCol('behaviors') // [] }) {
                    if ($wanted{$b}) { $found = 1; last ITEM; }
                }
            }
            if ($found) {
                my $faction_name = $climate->{dominant_faction_name} // '';
                my $traits_str   = join(', ', sort keys %$biases);
                push @suggestions, {
                    icon => 'PREMIUM',
                    text => _interpolate($advisories->{climate_match} // '', {
                        faction => $faction_name,
                        traits  => $traits_str,
                    }),
                    view => 'bazaar',
                };
            }
        }
    }

    if ($season && $shed_count > 0) {
        my $climate = $season->getCol('faction_climate') // {};
        my $banned  = $climate->{banned_traits} // [];
        if (@$banned) {
            my %banned = map { $_ => 1 } @$banned;
            my @matched;
            for my $shed (@$all_shed) {
                for my $b (@{ $shed->getCol('behaviors') // [] }) {
                    push @matched, $b if $banned{$b};
                }
            }
            if (@matched) {
                push @suggestions, {
                    icon => 'LOCK',
                    text => _interpolate($advisories->{banned_trait} // '', {
                        traits => join(', ', sort { $a cmp $b } @matched),
                    }),
                    view => 'bazaar',
                };
            }
        }
    }

    if ($scrap < 5) {
        push @suggestions, {
            icon => 'COIN',
            text => _interpolate($advisories->{scrap_low} // '', { scrap => $scrap }),
            view => 'prospect',
        };
    }

    return \@suggestions;
}

sub _interpolate ($text, $params) {
    $text =~ s!\{(\w+)\}!$params->{$1} // "{$1}"!ge;
    return $text;
}

1;
