package MagicMountain::Bot::Routine;
use Mojo::Base -base, -signatures;

use YAML::XS qw(LoadFile);
use MagicMountain::Bot::PushPolicy;
use MagicMountain::Bot::SellPolicy;
use MagicMountain::Bot::SkillPolicy;
use MagicMountain::Bot::PawnPolicy;
use MagicMountain::Bot::PressurePolicy;

my %PRESSURE_RANK = (
    mood_comfortable   => 0,
    mood_interested    => 1,
    mood_wary          => 2,
    mood_strained      => 3,
    mood_leaving       => 4,
    mood_over_absolute => 5,
);

sub _pressure_at_or_beyond ($state, $threshold) {
    return 0 unless $state && $threshold;
    return ($PRESSURE_RANK{$state} // 0) >= ($PRESSURE_RANK{$threshold} // 0);
}

has agent         => sub { die "agent required" };
has profile_file  => 'content/bots.yml';
has profile_id    => undef;
has transcript_cb => undef;

sub _ap_remaining ($self) {
    my $game = $self->agent->game;
    return $game->{player}{action_points} // 0;
}

sub load_profile ($self) {
    return {} unless $self->profile_id;
    my $file = $self->profile_file;
    my $profiles = -e $file ? LoadFile($file) : [];
    my ($p) = grep { $_->{id} eq $self->profile_id } @$profiles;
    return $p // {};
}

sub run_day ($self, $profile = undef) {
    $profile //= $self->load_profile;
    return { ok => 0, error => 'No bot profile' } unless $profile && $profile->{id};

    my $push_pol = $profile->{push_policy};
    my $sell_pol = $profile->{sell_policy};
    my $actions  = 0;

    $actions += $self->_prospect_phase($profile, $push_pol);
    $actions += $self->_market_phase($profile, $sell_pol);
    $self->_pawn_phase($profile);
    $self->_skill_phase($profile);
    $self->_pvp_phase($profile);

    $self->agent->logout;

    return { ok => 1, actions => $actions };
}

sub _prospect_phase ($self, $profile, $push_pol) {
    my $actions = 0;
    eval {
        my $res = $self->agent->begin_prospect;
        return unless $res->{ok};
        $actions++;

        # Event replaces prospecting entirely
        if ($res->{result} eq 'event') {
            my $choices = $res->{event}{choices};
            if ($choices && @$choices) {
                $self->agent->resolve_event($choices->[0]{id});
                $self->_log('event_choice', { choice_id => $choices->[0]{id} });
            }
            $self->agent->continue;
            $actions += 2;
            return;
        }
        if ($res->{result} eq 'event_passive') {
            $self->agent->continue;
            $actions++;
            return;
        }

        # Push loop
        while (1) {
            last if $self->_ap_remaining < 2;
            my $push_res = $self->agent->push;
            $actions++;
            last unless $push_res->{ok};

            if ($push_res->{result} eq 'collapse' || $push_res->{result} eq 'breakthrough') {
                $self->_log($push_res->{result}, { artifact => $push_res->{artifact} });
                last;
            }

            if ($push_res->{result} eq 'push') {
                $self->_log('push', { artifact => $push_res->{artifact} });
                my $art = $push_res->{artifact};
                if (MagicMountain::Bot::PushPolicy::evaluate($art, $push_pol)) {
                    my $stop_res = $self->agent->stop;
                    $actions++;
                    $self->_log('stop', { artifact => $stop_res->{artifact} }) if $stop_res->{ok};
                    last;
                }
            }
        }
    };
    warn "Prospecting error: $@" if $@;
    return $actions;
}

sub _market_phase ($self, $profile, $sell_pol) {
    return 0 unless $sell_pol;
    my $actions = 0;
    eval {
        # Hoarder skips market entirely
        return if ($sell_pol->{name} // '') eq 'hoarder';

        my $begin_res = $self->agent->begin_market;
        return unless $begin_res->{ok};
        $actions++;

        # Event replaces market entirely
        return if ($begin_res->{result} // '') eq 'event_passive';

        # Decide whether to accept the customer
        my $mkt = $self->agent->market;
        my $customer = $mkt->{market_visit};
        unless (MagicMountain::Bot::SellPolicy::accept_customer($customer, $sell_pol)) {
            $self->agent->send_away;
            $actions++;
            $self->_log('send_away', { reason => $sell_pol->{name} });
            return;
        }

        # Offer loop
        my $shed_res = $self->agent->shed;
        my $shed_items = $shed_res->{shed} // [];
        my $keep_offering = 1;
        my $max_irritation = $sell_pol->{params}{max_irritation} // 3;
        my $max_pressure_state = $sell_pol->{params}{max_pressure_state} // 'mood_wary';

        while ($keep_offering) {
            last if $self->_ap_remaining < 1;
            $shed_res = $self->agent->shed;
            my $current = $shed_res->{shed} // [];
            last unless @$current;

            for my $item (@$current) {
                next unless MagicMountain::Bot::SellPolicy::should_offer_item($item, $sell_pol);

                my $offer_res = $self->agent->offer($item->{id});
                $actions++;
                $self->_log('offer', { item_id => $item->{id}, result => $offer_res->{result} });

                if ($offer_res->{result} eq 'sold') {
                    $keep_offering = 0;
                    last;
                }

                if ($offer_res->{result} eq 'sold_more') {
                    if (_pressure_at_or_beyond($offer_res->{pressure_state}, $max_pressure_state)
                        || ($offer_res->{irritation} // 0) >= $max_irritation) {
                        $self->agent->send_away;
                        $actions++;
                    }
                    $keep_offering = 0;
                    last;
                }

                if ($offer_res->{result} eq 'counter_offer') {
                    my $decayed = $item->{decayed_value} // $item->{original_value} // 0;
                    if (MagicMountain::Bot::SellPolicy::should_accept_counter(
                            $offer_res->{counter_value}, $decayed, $sell_pol)) {
                        my $accept_res = $self->agent->accept_counter;
                        $actions++;
                        if ($accept_res->{ok} && $accept_res->{result} eq 'sold_more') {
                            if (_pressure_at_or_beyond($accept_res->{pressure_state}, $max_pressure_state)
                                || ($accept_res->{irritation} // 0) >= $max_irritation) {
                                $self->agent->send_away;
                                $actions++;
                            }
                        }
                        $keep_offering = 0;
                        last;
                    }
                    if (!MagicMountain::Bot::SellPolicy::try_another($offer_res, $customer, $sell_pol)) {
                        $keep_offering = 0;
                        last;
                    }
                    next;
                }

                if ($offer_res->{result} eq 'refused') {
                    $self->_log('refused', { item_id => $item->{id}, reason => $offer_res->{reason} });
                    next;
                }

                if ($offer_res->{result} eq 'over_budget' || $offer_res->{result} eq 'no_match') {
                    next;
                }

                if ($offer_res->{result} eq 'customer_left') {
                    $keep_offering = 0;
                    last;
                }
            }
            $keep_offering = 0;
        }

        # Clean up any lingering market negotiation so the character is
        # not stuck in "negotiating" phase on the next day.
        eval { $self->agent->send_away; $actions++ };
    };
    warn "Market error: $@" if $@;
    return $actions;
}

sub _pawn_phase ($self, $profile) {
    my $pawn_pol = $profile->{pawn_policy} // { name => 'always' };
    eval {
        my $pawn_res = $self->agent->pawn;
        return unless $pawn_res->{ok};
        return if $pawn_res->{pawn_closed};

        my $shed_res = $self->agent->shed;
        my @banned = grep { $_->{banned} } @{ $shed_res->{shed} // [] };
        return unless @banned;

        my $state = { consecutive_seizures => 0 };

        for my $item (@banned) {
            last if $self->_ap_remaining < 1;
            my $decision = MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pawn_pol);
            last if $decision eq 'stop';
            next if $decision eq 'skip';

            my $offer_res = $self->agent->offer_pawn($item->{id});
            $self->_log('offer_pawn', { item_id => $item->{id}, result => $offer_res->{result} });

            if ($offer_res->{result} eq 'seized') {
                $state->{consecutive_seizures}++;
            } else {
                $state->{consecutive_seizures} = 0;
            }
        }
    };
    warn "Pawn phase error: $@" if $@;
}

sub _skill_phase ($self, $profile) {
    my $policy_params = $profile->{skill_policy} // { name => 'never' };
    eval {
        my $game = $self->agent->game;
        my $skills_res = $self->agent->skills;

        my $p_skills = $game->{player}{skills} // {};
        my $state = { scrap => $game->{player}{scrap} // 0 };

        # Merge current skill levels into skill definitions
        my $skills = $skills_res->{skills} // [];
        for my $s (@$skills) {
            $s->{current_level} //= 0;
            if (defined $p_skills->{$s->{id}}) {
                $s->{current_level} = $p_skills->{$s->{id}};
            }
        }

        my $decision = MagicMountain::Bot::SkillPolicy::decide($state, $policy_params, $skills);
        if ($decision) {
            my $result = $self->agent->purchase_skill($decision->{skill_id});
            if ($result->{ok}) {
                $self->_log('policy_skill_purchase', $decision);
            }
        }
    };
    warn "Skill purchase error: $@" if $@;
}

sub _pvp_phase ($self, $profile) {
    eval {
        my $game = $self->agent->game;
        my $pvp_res = $self->agent->rivals;
        return unless $pvp_res->{ok} && !$pvp_res->{disabled};

        my $my_faction_sales = $game->{player}{faction_sales} // {};
        my $profile_pct = $profile->{pvp_aggressiveness};
        my $costs = {
            spoil_lead     => $pvp_res->{actions}[0]{cost} // 30,
            outbid         => $pvp_res->{actions}[1]{cost} // 75,
            corner_market  => $pvp_res->{actions}[2]{cost} // 50,
        };

        # Build stack counts per rival per faction from pressures data
        my %stack_counts;
        for my $p (@{ $pvp_res->{active_attacker} // [] }) {
            $stack_counts{ $p->{target_id} }{ $p->{faction_id} }++;
        }

        my $rivals = $pvp_res->{rivals} // [];
        for my $r (@$rivals) {
            $r->{stack_counts} = $stack_counts{ $r->{id} } // {};
        }

        my $context = {
            aggressiveness    => $profile_pct // 0.20,
            my_score          => $game->{player}{score} // 0,
            my_scrap          => $game->{player}{scrap} // 0,
            my_factions       => [ grep { ($my_faction_sales->{$_} // 0) >= 1 } keys %$my_faction_sales ],
            rivals            => $rivals,
            pressures_from_bot => $pvp_res->{active_attacker} // [],
            pvp_max_stack     => 3,
            pvp_costs         => $costs,
        };

        my $decision = MagicMountain::Bot::PressurePolicy->new->decide($context);
        if ($decision) {
            $self->agent->apply_pressure(%$decision);
            $self->_log('pressure_applied_bot', $decision);
        }
    };
    warn "PvP error: $@" if $@;
}

sub _log ($self, $type, $data) {
    return unless $self->transcript_cb;
    $self->transcript_cb->({ type => $type, %$data });
}

1;
