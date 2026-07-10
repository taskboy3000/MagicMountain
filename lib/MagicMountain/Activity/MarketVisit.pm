package MagicMountain::Activity::MarketVisit;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';


# ── Transition table ────────────────────────────────────────────────

has transitions => sub {
    { idle => ['begin'], negotiating => ['offer', 'send_away', 'accept_counter', 'stand_pat'] }
};

# ── Construction ──────────────────────────────────────────────────

sub create ($self, %params) {
    $params{type}  //= 'market_visit';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}

# ── Faction helpers ─────────────────────────────────────────────────

sub _factions ($self) {
    return $self->content_data->{factions} // [];
}

sub _weighted_faction ($self, $char) {
    my $factions = $self->_factions;
    my $standing = $char->getCol('standing') // {};
    my $snubs    = $char->getCol('faction_snubs') // {};

    my $total = 0;
    my @weights;
    for my $f (@$factions) {
        my $eff_standing = $standing->{$f->{id}} // 0;
        $eff_standing = 10 if $eff_standing > 10;
        my $w = 1.0 + ($eff_standing * 0.25);
        $w -= ($snubs->{$f->{id}} // 0) * 0.25;
        $w = 0.2 if $w < 0.2;
        push @weights, { faction => $f, weight => $w };
        $total += $w;
    }

    my $roll = rand($total);
    my $cumulative = 0;
    for my $entry (@weights) {
        $cumulative += $entry->{weight};
        return $entry->{faction} if $roll < $cumulative;
    }
    return $factions->[0];
}

sub _pick_behaviors ($self, $faction, $climate_biases = undef) {
    my $interests = $faction->{interests} // [];
    my $count = 1 + int(rand(scalar @$interests > 1 ? 3 : 1));
    my @pool;
    if ($climate_biases && keys %$climate_biases) {
        my %seen;
        for my $t (sort keys %$climate_biases) { $seen{$t} = 1; push @pool, $t; }
        for my $t (@$interests) { push @pool, $t unless $seen{$t}++; }
    } else {
        @pool = @$interests;
    }
    $count = scalar @pool if $count > scalar @pool;
    my @picked;
    for (1 .. $count) {
        last unless @pool;
        my $idx = int(rand(scalar @pool));
        push @picked, splice(@pool, $idx, 1);
    }
    return \@picked;
}

# ── Faction lookup ─────────────────────────────────────────────────────

sub _faction_by_id ($self, $faction_id) {
    my $factions = $self->_factions;
    for my $f (@$factions) {
        return $f if $f->{id} eq $faction_id;
    }
    return;
}

# ── Market dynamics ──────────────────────────────────────────────────

sub _dynamic_multiplier ($self, $season, $faction_id, $behaviors, $saturation_floor = undef) {
    my $faction = $self->_faction_by_id($faction_id) or return 1.0;
    my $fs      = $season->getCol('faction_state') // {};
    my $fdata   = $fs->{$faction_id};

    my $mult = $faction->{base_multiplier} // 1.0;
    return $mult unless $fdata;

    my $intake       = $fdata->{intake_by_trait} // {};
    my $sat_rate     = $self->app->config->{market_trait_saturation_rate} // 0.02;
    my $max_discount = $self->app->config->{market_max_saturation_discount} // 0.50;
    my $total_discount = 0;
    for my $trait (@$behaviors) {
        $total_discount += $sat_rate * ($intake->{$trait} // 0);
    }
    $total_discount = $max_discount if $total_discount > $max_discount;
    my $sat_factor = 1 - $total_discount;
    # Pressure saturation floor: one-way clamp downward (Corner the Market).
    # If set, the saturation factor is reduced to the floor, never raised.
    $sat_factor = $saturation_floor
        if defined $saturation_floor && $sat_factor > $saturation_floor;
    $mult *= $sat_factor;

    if ($self->app->can('dominance_service') && (my $season = $self->app->active_season)) {
        my $dom = $self->app->dominance_service;
        if ($dom->saturation_floor_active($season, $faction_id, $behaviors->[0] // '')) {
            $mult = $faction->{base_multiplier} if $mult < $faction->{base_multiplier};
        }
    }

    my $daily_intake  = $fdata->{daily_intake} // 0;
    my $appetite_base = $faction->{daily_appetite_base} // 3;
    if ($self->app->can('dominance_service') && (my $aseason = $self->app->active_season)) {
        $appetite_base += $self->app->dominance_service->appetite_delta($aseason);
    }
    $appetite_base = 1 if $appetite_base < 1;
    if ($daily_intake >= $appetite_base) {
        $mult *= ($self->app->config->{market_post_appetite_penalty} // 0.50);
    }

    my $days_idle        = $fdata->{days_since_purchase} // 0;
    my $desperation_days = $faction->{desperation_days} // 3;
    if ($days_idle >= $desperation_days) {
        $mult *= ($self->app->config->{market_desperation_bonus} // 1.30);
    }

    return $mult;
}

# ── Loyalty bonus ────────────────────────────────────────────────────

sub _apply_loyalty_bonus ($self, $char, $faction_id, $offer_value) {
    my $sales = $char->getCol('faction_sales') // {};
    return ($sales->{$faction_id} // 0) >= 3
        ? int($offer_value * 1.05)
        : $offer_value;
}

# ── Narrative reactions ───────────────────────────────────────────────

sub _pick_reaction ($self, $faction_id, $outcome, %params) {
    my $reactions = $self->app->negotiation_reactions // {};
    my $msgs = $reactions->{$faction_id}{$outcome} or return;
    my $text = $msgs->[ int(rand(scalar @$msgs)) ] or return;
    $text =~ s!\{(\w+)\}!$params{$1} // "{$1}"!ge;
    return $text;
}

# ═══════════════════════════════════════════════════════════════════════
# HANDLERS
# ═══════════════════════════════════════════════════════════════════════

# ── begin ─────────────────────────────────────────────────────────────

sub begin ($self, $char, %params) {
    die "AP exhausted" unless ($char->getCol('action_points') // 0) >= 1;

    my $shed_items = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );
    die "no items in shed" unless @$shed_items;

    # Check: if all items are banned by the dominant faction, don't waste AP
    if ($self->app->can('market_gate') && $self->app->market_gate->should_route_to_black_market($char)) {
        my $season = $self->app->active_season;
        my $climate = $season->getCol('faction_climate') // {};
        my @banned = @{ $climate->{banned_traits} // [] };
        if (@banned) {
            # Check if ALL items are banned
            my $all_banned = 1;
            for my $item (@$shed_items) {
                my $behaviors = $item->getCol('behaviors') // [];
                my $has_non_banned = 0;
                for my $b (@$behaviors) {
                    if (!grep { $_ eq $b } @banned) {
                        $has_non_banned = 1;
                        last;
                    }
                }
                if ($has_non_banned) {
                    $all_banned = 0;
                    last;
                }
            }
            if ($all_banned) {
                return {
                    view => {
                        ok      => 1,
                        result  => 'all_items_banned',
                        message => 'All items in your shed are restricted by the dominant faction. The broker awaits.',
                        player  => $self->_player_snapshot($char),
                    },
                };
            }
        }
    }

    # Check for random event FIRST — replaces the market visit
    if ($self->app->can('random_events')) {
        my $season = $self->app->can('active_season') ? $self->app->active_season : undef;
        my $fs = $season ? $season->getCol('faction_state') // {} : {};
        my $standing = $char->getCol('standing') // {};
        my $event = $self->app->random_events->draw(
            pool    => 'market_visit',
            trigger => 'begin',
            context => {
                char          => $char,
                standing      => $standing,
                faction_state => $fs,
                season        => $season,
            },
        );
        if ($event) {
            my $name = $char->getCol('name') // 'unknown';
            $self->app->log->info(
                sprintf("Market event [%s] %s — %s", $event->{id}, $name, $event->{text})
            );
            $self->_log_event($char, {
                type       => 'random_event',
                event_id   => $event->{id},
                narrative  => sprintf("%s encountered market event %s: %s", $name, $event->{id}, $event->{text}),
            });
            my $detail;
            if ($event->{result}) {
                $detail = $event->{result};
            } elsif (my $resolved = $event->{_resolved_effects}) {
                $detail = $self->app->random_events->describe_effects($resolved, 'market_visit');
            }
            chomp $detail if $detail;
            # No AP consumed — the event replaced the market visit
            $self->delete;
            $char->setCol('pending_activity_id', undef);
            $char->setCol('result', {
                outcome      => 'event_passive',
                icon         => 'NOTICE',
                outcome_text => 'Market Event',
                message      => $event->{text},
                detail       => $detail,
                activity_type => 'market',
            });
            $char->setCol('current_view', 'result');
            $char->save;
            return {
                view => {
                    ok      => 1,
                    result  => 'event_passive',
                    event   => { id => $event->{id}, text => $event->{text} },
                    player  => $self->_player_snapshot($char),
                },
            };
        }
    }

    my $faction = $self->_weighted_faction($char);

    # ── Loyalty access guarantee ───────────────────────────────────
    my $faction_sales = $char->getCol('faction_sales') // {};
    my ($top_faction, $top_count) = (undef, 0);
    while (my ($fid, $cnt) = each %$faction_sales) {
        ($top_faction, $top_count) = ($fid, $cnt) if $cnt > $top_count;
    }
    if ($top_faction && $top_count >= 2) {
        my $visits_since = $char->getCol('loyalty_visits_since') // 0;
        if ($faction->{id} ne $top_faction && $visits_since >= 3) {
            $faction = $self->_faction_by_id($top_faction) // $faction;
            $visits_since = 0;
        } elsif ($faction->{id} eq $top_faction) {
            $visits_since = 0;
        } else {
            $visits_since++;
        }
        $char->setCol('loyalty_visits_since', $visits_since);
        $char->save;
    }
    # ────────────────────────────────────────────────────────────────

    my $standing = $char->getCol('standing') // {};
    my $mult_bonus = ($standing->{$faction->{id}} // 0) * 0.05;
    my $sell = $char->getCol('skill_selling') // 0;

    my $base_budget = 30 + int(rand(30));
    my $standing_bonus = ($standing->{$faction->{id}} // 0) * 5;
    my $soft_budget = $base_budget + $standing_bonus;
    my $sales_to_faction = ($faction_sales->{$faction->{id}} // 0);
    my $portrait_id;
    if (eval { $self->app->customer_portraits; 1 }) {
        my $portraits = $self->app->customer_portraits;
        $portrait_id = @$portraits ? $portraits->[rand @$portraits] : undef;
    }
    # ── Climate trait biases (extracted before customer struct) ─────
    my $climate_biases = {};
    if ($self->app->can('dominance_service') && (my $season = $self->app->active_season)) {
        my $dom = $self->app->dominance_service;
        my $biases = $dom->buyer_trait_biases($season);
        $climate_biases = $biases if keys %$biases;

        $soft_budget += $dom->budget_delta($season);
    }

    my $customer = {
        faction_id          => $faction->{id},
        faction_name        => $faction->{name},
        disposition         => $faction->{disposition},
        portrait_id         => $portrait_id,
        desired_behaviors   => $self->_pick_behaviors($faction, $climate_biases),
        base_multiplier     => ($faction->{base_multiplier} // 1.0) + $mult_bonus,
        offer_value         => undef,
        irritation          => int(rand(4)),
        irritation_threshold => 4,
        settle_chance       => $faction->{settle_chance} // 0.15,
        soft_budget         => $soft_budget,
        absolute_budget     => int($soft_budget * 1.2),
        spent_so_far        => 0,
        loyalty_free_mismatches => $sales_to_faction >= 1 ? 1 : 0,
        (keys %$climate_biases ? (climate_trait_biases => $climate_biases) : ()),
    };

    # ── Faction climate: patience delta for dominant faction ────────
    if (keys %$climate_biases) {
        my $season = $self->app->active_season;
        my $dom = $self->app->dominance_service;
        if ($customer->{faction_id} eq ($dom->dominant_faction($season) // '')) {
            $customer->{irritation_threshold} += $dom->patience_delta($season);
        }
    }
    # ── Faction climate: mood delta (market-wide) ─────────────────
    if ($self->app->can('dominance_service') && (my $mseason = $self->app->active_season)) {
        my $mdom = $self->app->dominance_service;
        $customer->{irritation} -= $mdom->mood_delta($mseason);
        $customer->{irritation} = 0 if $customer->{irritation} < 0;
    }
    # ────────────────────────────────────────────────────────────────

    # ── Rival Pressure: consume effects that fire on visit begin ────
    my $pvp = $self->app->can('pvp_service') ? $self->app->pvp_service : undef;
    if ($pvp) {
        my $eff_t = $pvp->consume_target_effects(
            $char->getCol('id'), $customer->{faction_id}, 'on_begin');
        my $eff_a = $pvp->consume_attacker_splashbacks(
            $char->getCol('id'), $customer->{faction_id}, 'on_begin');
        $customer->{irritation} = $eff_t->{irritation_floor} // $eff_a->{irritation_floor}
            // $customer->{irritation};
        $customer->{absolute_budget} = int($customer->{absolute_budget}
            * ($eff_t->{budget_ratio} // $eff_a->{budget_ratio} // 1.0));
    }
    # ────────────────────────────────────────────────────────────────

    $char->setCol('action_points', $char->getCol('action_points') - 1);
    $self->customer($customer);
    $self->phase('negotiating');
    $self->save;
    $char->setCol('pending_activity_id', $self->getCol('id'));
    $char->save;

    $self->_log_event($char, {
        type         => 'market_visit',
        faction_id   => $faction->{id},
        faction_name => $faction->{name},
        narrative    => sprintf("%s visits the Bazaar. A buyer from %s approaches.",
            $char->getCol('name') // 'unknown', $faction->{name}),
    });

    my $budget_range = ($sell >= 3) ? {
        budget_min => $customer->{soft_budget},
        budget_max => $customer->{absolute_budget},
    } : undef;

    return {
        view => {
            ok       => 1,
            result   => 'negotiating',
            (defined $budget_range ? (budget => $budget_range) : ()),
            customer => {
                faction_id   => $faction->{id},
                faction_name => $faction->{name},
                disposition  => $faction->{disposition} // 'unknown',
            },
            player => $self->_player_snapshot($char),
        },
    };
}

# ── offer ─────────────────────────────────────────────────────────────

sub offer ($self, $char, %params) {
    my $shed_item_id = $params{shed_item_id} or die "shed_item_id is required";
    my $customer     = $self->customer or die "no customer";

    # Clear last_message on new offer
    $customer->{last_message} = undef;
    $customer->{last_sale} = undef;

    # Auto-accept if same item is re-offered with pending counter
    if ($customer->{pending_counter} && $customer->{pending_counter}{item_id} eq $shed_item_id) {
        my $counter_value = $customer->{pending_counter}{value};
        $customer->{pending_counter} = undef;
        $self->customer($customer);
        my $item = $self->app->shed->get($shed_item_id);
        die "shed item not found" unless $item;
        die "shed item belongs to another character"
            unless $item->getCol('char_id') eq $char->getCol('id');
        return $self->_do_sale($char, $item, $counter_value, 'counter');
    }

    # Clear any pending counter for a different item
    $customer->{pending_counter} = undef;

    my $item = $self->app->shed->get($shed_item_id);
    die "shed item not found" unless $item;
    die "shed item belongs to another character"
        unless $item->getCol('char_id') eq $char->getCol('id');

    my $intersect = 0;
    for my $behavior (@{ $item->getCol('behaviors') // [] }) {
        if (grep { $_ eq $behavior } @{ $customer->{desired_behaviors} // [] }) {
            $intersect = 1;
            last;
        }
    }

    # ── Banned trait check (dominant faction refuses restricted goods) ──
    my $season_bm = $self->app->active_season;
    if ($season_bm && $self->app->can('dominance_service')) {
        my $climate = $season_bm->getCol('faction_climate') // {};
        my @banned = @{ $climate->{banned_traits} // [] };
        if (@banned && $customer->{faction_id} eq ($climate->{dominant_faction} // '')) {
            my $item_behaviors = $item->getCol('behaviors') // [];
            for my $bt (@banned) {
                if (grep { $_ eq $bt } @$item_behaviors) {
                    my $narrative = sprintf("%s examines the item and shakes their head. 'We do not handle that class of object. Try a less... visible market.'", $customer->{faction_name});
                    return {
                        view => {
                            ok      => 1,
                            result  => 'refused',
                            reason  => 'banned_trait',
                            message => $narrative,
                            player  => $self->_player_snapshot($char),
                        },
                    };
                }
            }
        }
    }

    my $decayed  = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
    my $sell     = $char->getCol('skill_selling') // 0;
    my $season   = $self->app->active_season;
    # PvP: consume on_sale effects and pass saturation floor to multiplier.
    my $pvp = $self->app->can('pvp_service') ? $self->app->pvp_service : undef;
    my $sat_floor;
    if ($pvp) {
        my $eff = $pvp->consume_target_effects(
            $char->getCol('id'), $customer->{faction_id}, 'on_sale');
        my $spl = $pvp->consume_attacker_splashbacks(
            $char->getCol('id'), $customer->{faction_id}, 'on_sale');
        # Take the worse of the two (one-way clamp downward per §17 #13)
        $sat_floor = ($eff->{saturation_floor} // 1.0);
        my $s = $spl->{saturation_floor} // 1.0;
        $sat_floor = $s if $s < $sat_floor;
    }
    my $dyn_mult = $season
        ? $self->_dynamic_multiplier($season, $customer->{faction_id}, $item->getCol('behaviors') // [], $sat_floor)
        : ($customer->{base_multiplier} // 1.0);
    my $offer_value;

    if ($intersect) {
        my $match_mult = $sell >= 3 ? 1.4 : 1.2;
        my $base_match = $match_mult;
        if ($customer->{climate_trait_biases}) {
            for my $b (@{ $item->getCol('behaviors') // [] }) {
                $match_mult *= (1 + ($customer->{climate_trait_biases}->{$b} // 0));
            }
        }
        $customer->{climate_premium_pct} = $match_mult > $base_match
            ? int(($match_mult / $base_match - 1) * 100 + 0.5) : 0;
        $offer_value = int($decayed * $dyn_mult * $match_mult);
        $offer_value = $self->_apply_loyalty_bonus($char, $customer->{faction_id}, $offer_value);
        my $narrative = $self->_pick_reaction($customer->{faction_id}, 'match',
            item_id => $item->getCol('artifact_id'), value => $offer_value,
        ) // sprintf("%s offers %d scrap for the item. Match!", $customer->{faction_name}, $offer_value);
        $self->_log_event($char, {
            type          => 'offer',
            shed_item_id  => $shed_item_id,
            faction_id    => $customer->{faction_id},
            match         => 1,
            offered_value => $offer_value,
            accepted      => 1,
            narrative     => $narrative,
        });
        return $self->_do_sale($char, $item, $offer_value, 'match');
    } else {
        $offer_value = int($decayed * $dyn_mult * 0.5);

        my $settle_chance = $customer->{settle_chance} // 0.15;
        if (rand() < $settle_chance) {
            $offer_value = $self->_apply_loyalty_bonus($char, $customer->{faction_id}, $offer_value);
            my $narrative = $self->_pick_reaction($customer->{faction_id}, 'settle',
                item_id => $item->getCol('artifact_id'), value => $offer_value,
            ) // sprintf("%s shrugs and accepts %d scrap.", $customer->{faction_name}, $offer_value);
            $self->_log_event($char, {
                type          => 'offer',
                shed_item_id  => $shed_item_id,
                faction_id    => $customer->{faction_id},
                match         => 0,
                settle        => 1,
                offered_value => $offer_value,
                accepted      => 1,
                narrative     => $narrative,
            });
            return $self->_do_sale($char, $item, $offer_value, 'settle');
        }

        # ── Counter-offer (haggle) ────────────────────────────────
        if ($self->app->can('config') && $self->app->config->{market_counter_offers}) {
            my $standing = $char->getCol('standing') // {};
            my $counter_pct = 0.75;
            $counter_pct = 0.80 if $sell >= 2;
            $counter_pct += ($standing->{$customer->{faction_id}} // 0) * 0.01;
            $counter_pct = 0.95 if $counter_pct > 0.95;

            my $counter_value = int($decayed * $dyn_mult * $counter_pct);

            # Cap the counter at the customer's remaining budget
            my $remaining = ($customer->{absolute_budget} // 999999) - ($customer->{spent_so_far} // 0);
            $counter_value = $remaining if $counter_value > $remaining;

            # ── Budget exhausted: can't offer a 0-scrap counter ──
            if ($remaining <= 0) {
                my $narrative = sprintf("%s taps their empty purse. \"That's all I've got for today.\"",
                    $customer->{faction_name});
                $char->setCol('result', {
                    outcome      => 'maxed_out',
                    icon         => 'STAR',
                    outcome_text => 'Sale Maxed Out!',
                    total        => $customer->{spent_so_far},
                    message      => sprintf('Congratulations! The customer spent %d scrap in total!', $customer->{spent_so_far}),
                });
                $char->setCol('current_view', 'result');
                $self->phase('idle');
                $self->customer(undef);
                $self->delete;
                $char->setCol('pending_activity_id', undef);
                $char->save;
                $self->_log_event($char, {
                    type          => 'budget_exhausted',
                    shed_item_id  => $shed_item_id,
                    faction_id    => $customer->{faction_id},
                    remaining     => $remaining,
                    narrative     => $narrative,
                });
                return {
                    view => {
                        ok      => 1,
                        result  => 'maxed_out',
                        message => $narrative,
                        player  => $self->_player_snapshot($char),
                    },
                };
            }

            $customer->{pending_counter} = { value => $counter_value, item_id => $shed_item_id };
            $customer->{last_message} = undef;
            $self->customer($customer);
            $self->save;

            my $narrative = $self->_pick_reaction($customer->{faction_id}, 'counter',
                item_id => $item->getCol('artifact_id'), value => $counter_value,
            ) // sprintf("%s considers your offer. \"How about %d scrap?\"", $customer->{faction_name}, $counter_value);

            $self->_log_event($char, {
                type          => 'counter_offer',
                shed_item_id  => $shed_item_id,
                faction_id    => $customer->{faction_id},
                offered_value => $counter_value,
                narrative     => $narrative,
            });

            return {
                view => {
                    ok            => 1,
                    result        => 'counter_offer',
                    counter_value => $counter_value,
                    irritation    => $customer->{irritation},
                    message       => $narrative,
                    player        => $self->_player_snapshot($char),
                },
            };
        }

        # ── No counter-offers: existing behavior ──────────────────
        if ($customer->{loyalty_free_mismatches} && $customer->{loyalty_free_mismatches} > 0) {
            $customer->{loyalty_free_mismatches}--;
        } else {
            my $irritation_gain = 1;
            $irritation_gain = 0 if $sell >= 2;
            $customer->{irritation} += $irritation_gain;
        }

        if ($customer->{irritation} >= $customer->{irritation_threshold}) {
            my $narrative = $self->_pick_reaction($customer->{faction_id}, 'storm_off',
                item_id => $item->getCol('artifact_id'), value => $offer_value,
            ) // sprintf("%s storms off in frustration.", $customer->{faction_name});
            $self->_log_event($char, {
                type          => 'offer',
                shed_item_id  => $shed_item_id,
                faction_id    => $customer->{faction_id},
                match         => 0,
                offered_value => $offer_value,
                accepted      => 0,
                irritation    => $customer->{irritation},
                narrative     => $narrative,
            });
            $char->setCol('result', {
                outcome      => 'customer_left',
                icon         => 'ALERT',
                outcome_text => 'Customer Stormed Off',
                message      => $narrative,
                item_name    => $item->getCol('artifact_id'),
            });
            $char->setCol('current_view', 'result');
            $self->phase('idle');
            $self->customer(undef);
            $self->delete;
            $char->setCol('pending_activity_id', undef);
            $char->save;
            return {
                view => {
                    ok      => 1,
                    result  => 'customer_left',
                    message => $narrative,
                    player  => $self->_player_snapshot($char),
                },
            };
        }

        my $narrative = $self->_pick_reaction($customer->{faction_id}, 'mismatch',
            item_id => $item->getCol('artifact_id'), value => $offer_value,
        ) // sprintf("%s frowns but gestures for you to try another item.", $customer->{faction_name});
        $self->_log_event($char, {
            type          => 'offer',
            shed_item_id  => $shed_item_id,
            faction_id    => $customer->{faction_id},
            match         => 0,
            offered_value => $offer_value,
            accepted      => 0,
            irritation    => $customer->{irritation},
            narrative     => $narrative,
        });
        $customer->{last_message} = $narrative;
        $self->customer($customer);
        $self->save;
        return {
            view => {
                ok        => 1,
                result    => 'no_match',
                irritation => $customer->{irritation},
                message   => $narrative,
                player    => $self->_player_snapshot($char),
            },
        };
    }
}

# ── accept_counter ────────────────────────────────────────────────────

sub accept_counter ($self, $char, %params) {
    my $customer = $self->customer or die "no customer";
    my $pc       = $customer->{pending_counter} or die "no pending counter";

    my $item = $self->app->shed->get($pc->{item_id});
    die "shed item not found" unless $item;
    die "shed item belongs to another character"
        unless $item->getCol('char_id') eq $char->getCol('id');

    my $counter_value = $pc->{value};
    $customer->{pending_counter} = undef;
    $self->customer($customer);

    $self->_log_event($char, {
        type          => 'accept_counter',
        shed_item_id  => $pc->{item_id},
        faction_id    => $customer->{faction_id},
        offered_value => $counter_value,
        accepted      => 1,
        narrative     => sprintf("You accept %d scrap from %s.", $counter_value, $customer->{faction_name}),
    });

    return $self->_do_sale($char, $item, $counter_value, 'counter');
}

# ── stand_pat ─────────────────────────────────────────────────────────

sub stand_pat ($self, $char, %params) {
    my $customer = $self->customer or die "no customer";
    my $pc       = $customer->{pending_counter} or die "no pending counter";

    my $item = $self->app->shed->get($pc->{item_id});
    die "shed item not found" unless $item;
    die "shed item belongs to another character"
        unless $item->getCol('char_id') eq $char->getCol('id');

    my $decayed   = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
    my $season    = $self->app->active_season;
    my $pvp = $self->app->can('pvp_service') ? $self->app->pvp_service : undef;
    my $sat_floor;
    if ($pvp) {
        my $eff = $pvp->consume_target_effects(
            $char->getCol('id'), $customer->{faction_id}, 'on_sale');
        my $spl = $pvp->consume_attacker_splashbacks(
            $char->getCol('id'), $customer->{faction_id}, 'on_sale');
        $sat_floor = ($eff->{saturation_floor} // 1.0);
        my $s = $spl->{saturation_floor} // 1.0;
        $sat_floor = $s if $s < $sat_floor;
    }
    my $dyn_mult  = $season
        ? $self->_dynamic_multiplier($season, $customer->{faction_id}, $item->getCol('behaviors') // [], $sat_floor)
        : ($customer->{base_multiplier} // 1.0);
    my $stand_price = int($decayed * $dyn_mult);

    my $sell     = $char->getCol('skill_selling') // 0;
    my $standing = $char->getCol('standing') // {};
    my $stand_pct = $standing->{$customer->{faction_id}} // 0;

    my $chance = 0.30 + ($sell * 0.15) + ($stand_pct * 0.02);
    $chance = 0.85 if $chance > 0.85;

    if (rand() < $chance) {
        $customer->{pending_counter} = undef;
        $customer->{last_message} = sprintf("%s relents and accepts your price of %d scrap.",
            $customer->{faction_name}, $stand_price);
        $self->customer($customer);
        $self->save;

        $self->_log_event($char, {
            type          => 'stand_pat',
            shed_item_id  => $pc->{item_id},
            faction_id    => $customer->{faction_id},
            offered_value => $stand_price,
            narrative     => sprintf("%s holds firm for %d scrap from %s — customer accepts.",
                $char->getCol('name'), $stand_price, $customer->{faction_name}),
        });

        return $self->_do_sale($char, $item, $stand_price, 'stand_pat');
    }

    $customer->{irritation} += 1.5;
    $customer->{pending_counter} = $pc;
    $customer->{last_message} = sprintf("%s refuses your demand and looks annoyed.",
        $customer->{faction_name});

    if ($customer->{irritation} >= $customer->{irritation_threshold}) {
        my $narrative = $self->_pick_reaction($customer->{faction_id}, 'storm_off',
            item_id => $item->getCol('artifact_id'), value => $stand_price,
        ) // sprintf("%s storms off in frustration.", $customer->{faction_name});
        $self->_log_event($char, {
            type          => 'stand_pat',
            shed_item_id  => $pc->{item_id},
            faction_id    => $customer->{faction_id},
            match         => 0,
            offered_value => $stand_price,
            accepted      => 0,
            irritation    => $customer->{irritation},
            narrative     => $narrative,
        });
        $char->setCol('result', {
            outcome      => 'customer_left',
            icon         => 'ALERT',
            outcome_text => 'Customer Stormed Off',
            message      => $narrative,
            item_name    => $item->getCol('artifact_id'),
        });
        $char->setCol('current_view', 'result');
        $self->phase('idle');
        $self->customer(undef);
        $self->delete;
        $char->setCol('pending_activity_id', undef);
        $char->save;
        return {
            view => {
                ok      => 1,
                result  => 'customer_left',
                message => $narrative,
                player  => $self->_player_snapshot($char),
            },
        };
    }

    $self->customer($customer);
    $self->save;

    $self->_log_event($char, {
        type          => 'stand_pat_fail',
        shed_item_id  => $pc->{item_id},
        faction_id    => $customer->{faction_id},
        offered_value => $stand_price,
        irritation    => $customer->{irritation},
        narrative     => sprintf("%s refuses stand-pat demand for %d scrap from %s.",
            $char->getCol('name'), $stand_price, $customer->{faction_name}),
    });

    return {
        view => {
            ok        => 1,
            result    => 'stand_pat_refused',
            irritation => $customer->{irritation},
            message   => $customer->{last_message},
            player    => $self->_player_snapshot($char),
        },
    };
}

# ── send_away ─────────────────────────────────────────────────────────

sub send_away ($self, $char, %params) {
    my $faction_id = $self->customer->{faction_id};
    if ($faction_id) {
        my $snubs = $char->getCol('faction_snubs') // {};
        $snubs->{$faction_id}++;
        $char->setCol('faction_snubs', $snubs);
    }

    my $spent = $self->customer->{spent_so_far} // 0;
    if ($spent == 0) {
        my $ap  = $char->getCol('action_points') // 0;
        my $max = $char->getCol('action_points_max') // 99;
        $char->setCol('action_points', ($ap + 1) < $max ? ($ap + 1) : $max);
    }

    my $season = $self->app->active_season;
    if ($season && $faction_id) {
        my $day = $season->getCol('day') // 0;
        my $snub_day = $char->getCol('snub_day') // 0;
        if ($day != $snub_day) {
            $char->setCol('snub_day', $day);
            my $fs = $season->getCol('faction_state') // {};
            for my $fid (keys %$fs) {
                next if $fid eq $faction_id;
                $fs->{$fid}->{influence} = ($fs->{$fid}->{influence} // 0) + 1;
            }
            $season->setCol('faction_state', $fs);
            $season->save;
            $self->_log_event($char, {
                type        => 'influence_snub',
                faction_id  => $faction_id,
                narrative   => sprintf("%s snubbed %s — all other factions gain +1 influence.",
                    $char->getCol('name') // 'unknown', $self->customer->{faction_name} // $faction_id),
            });
        }
    }

    $char->setCol('result', {
        outcome      => 'sent_away',
        icon         => 'WAIT',
        outcome_text => 'No Sale',
        message      => 'You send the customer away.',
    });
    $char->setCol('current_view', 'result');

    $self->_log_event($char, {
        type        => 'send_away',
        narrative   => sprintf("%s sends the customer away.", $char->getCol('name') // 'unknown'),
    });

    $self->phase('idle');
    $self->customer(undef);
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    return {
        view => {
            ok      => 1,
            result  => 'sent_away',
            message => 'You send the customer away.',
            player  => $self->_player_snapshot($char),
        },
    };
}

# ═══════════════════════════════════════════════════════════════════════
# INTERNAL OUTCOMES
# ═══════════════════════════════════════════════════════════════════════

sub budget_pressure_state ($self, $customer) {
    my $budget = $customer->{soft_budget} or return { state => 'mood_comfortable', display => 'COMFORTABLE', pct => 0 };
    my $pct = ($customer->{spent_so_far} // 0) / $budget;
    my ($state, $display);
    if    ($pct <= 0.50) { $state = 'mood_comfortable'; $display = 'COMFORTABLE' }
    elsif ($pct <= 0.80) { $state = 'mood_interested';  $display = 'INTERESTED' }
    elsif ($pct <= 1.00) { $state = 'mood_wary';        $display = 'WARY' }
    elsif ($pct <= 1.10) { $state = 'mood_strained';    $display = 'STRAINED' }
    elsif ($pct <  1.20) { $state = 'mood_leaving';     $display = 'STRAINED' }
    else                 { $state = 'mood_over_absolute'; $display = 'OVER LIMIT' }
    return { state => $state, display => $display, pct => $pct };
}

sub _over_budget ($self, $char, $item, $value) {
    my $customer = $self->customer;
    $customer->{irritation} += 2;

    my $narrative = $self->_pick_reaction($customer->{faction_id}, 'over_absolute',
        item_id => $item->getCol('artifact_id'), value => $value,
    ) // sprintf("The buyer shakes their head. 'I don't have that much scrap.'");

    $customer->{last_message} = $narrative;
    $self->customer($customer);
    $self->save;

    $self->_log_event($char, {
        type          => 'over_budget',
        shed_item_id  => $item->getCol('id'),
        faction_id    => $customer->{faction_id},
        offered_value => $value,
        irritation    => $customer->{irritation},
        narrative     => $narrative,
    });

    return {
        view => {
            ok      => 1,
            result  => 'over_budget',
            irritation => $customer->{irritation},
            message => $narrative,
            player  => $self->_player_snapshot($char),
        },
    };
}

sub _do_sale ($self, $char, $item, $value, $sale_type) {
    my $customer = $self->customer;

    # ── Over-absolute check ──────────────────────────────────────
    my $new_spent = ($customer->{spent_so_far} // 0) + $value;
    if ($new_spent > ($customer->{absolute_budget} // 999999)) {
        return $self->_over_budget($char, $item, $value);
    }

    # ── Track budget ─────────────────────────────────────────────
    $customer->{spent_so_far} = $new_spent;
    my $abs_budget = $customer->{absolute_budget} // 999999;
    my $over_soft  = $new_spent > ($customer->{soft_budget} // 999999);

    # ── Budget exhausted: maxed out this sale (precision bonus can't
    #    fire because we're at >=100%, so bonus_base is 0) ─────────
    if ($new_spent >= $abs_budget) {
        my $maxed_bonus = int($value * 0.20);
        $char->setCol('scrap', $char->getCol('scrap') + $value + $maxed_bonus);
        $char->setCol('score', $char->getCol('score') + $value + $maxed_bonus);

        # ── Standing ──────────────────────────────────────────────
        my $fid = $customer->{faction_id};
        my $sales    = $char->getCol('faction_sales') // {};
        my $standing = $char->getCol('standing') // {};

        $sales->{$fid}++;
        my $total_to_faction = $sales->{$fid} // 0;
        my $delta;
        if ($sale_type eq 'match') {
            $delta = $over_soft ? 1 : 2;
        } else {
            $delta = ($sale_type eq 'counter' || $sale_type eq 'stand_pat') ? 1 : 0;
        }
        $delta++ if $item->getCol('has_evolved');
        $delta++ if $total_to_faction >= 2;
        $delta++ if $total_to_faction >= 4;
        $standing->{$fid} += $delta;

        $char->setCol('faction_sales', $sales);
        $char->setCol('standing', $standing);

        my $snubs = $char->getCol('faction_snubs') // {};
        delete $snubs->{$fid};
        $char->setCol('faction_snubs', $snubs);

        # ── Faction state ───────────────────────────────────────
        my $season = $self->app->active_season;
        if ($season) {
            my $fs = $season->getCol('faction_state') // {};
            $fs->{$fid}->{name}                //= $customer->{faction_name};
            $fs->{$fid}->{influence}            += $value + $maxed_bonus;
            $fs->{$fid}->{artifacts_received}++;
            $fs->{$fid}->{daily_intake}++;
            $fs->{$fid}->{days_since_purchase} = 0;
            for my $t (@{ $item->getCol('behaviors') // [] }) {
                $fs->{$fid}->{intake_by_trait}->{$t}++;
            }
            $season->setCol('faction_state', $fs);
            $season->save;
        }

        $self->app->shed->delete($item->getCol('id'));
        $self->_record_disposition($char, $item, $value + $maxed_bonus, $delta, $fid) if $season;

        $customer->{last_message} = undef;
        $customer->{last_sale} = {
            value               => $value,
            sale_type           => $sale_type,
            precision_bonus     => 0,
            maxed_bonus         => $maxed_bonus,
            total               => $new_spent,
            climate_premium_pct => $customer->{climate_premium_pct} || 0,
        };

        $char->setCol('result', {
            outcome      => 'maxed_out',
            icon         => 'STAR',
            outcome_text => 'Sale Maxed Out!',
            item_name    => $item->getCol('artifact_id'),
            value        => $value,
            bonus        => $maxed_bonus,
            total        => $new_spent,
            message      => sprintf('Congratulations! You maxed out this sale! Total: %d scrap (+%d bonus).',
                $new_spent, $maxed_bonus),
        });
        $char->setCol('current_view', 'result');
        $self->customer($customer);
        $self->delete;
        $char->setCol('pending_activity_id', undef);
        $char->save;

        $self->_log_event($char, {
            type          => 'sale_maxed',
            shed_item_id  => $item->getCol('id'),
            faction_id    => $customer->{faction_id},
            value         => $value,
            sale_type     => $sale_type,
            spent_so_far  => $customer->{spent_so_far},
            soft_budget   => $customer->{soft_budget},
            maxed_bonus   => $maxed_bonus,
            narrative     => sprintf("Sale maxed out! Sold to %s for %d scrap (%d total, +%d bonus).",
                $customer->{faction_name}, $value, $new_spent, $maxed_bonus),
        });

        return {
            view => {
                ok                  => 1,
                result              => 'maxed_out',
                value               => $value,
                bonus               => $maxed_bonus,
                total               => $new_spent,
                sale_type           => $sale_type,
                sold_item_id        => $item->getCol('id'),
                climate_premium_pct => $customer->{climate_premium_pct} || 0,
                player              => $self->_player_snapshot($char),
            },
        };
    }

    # ── Precision bonus (within 5% of absolute, < 100%) ──────────
    my $bonus = 0;
    my $pct_of_abs = $new_spent / ($customer->{absolute_budget} // 1);
    if ($pct_of_abs >= 0.95 && $pct_of_abs < 1.0) {
        $bonus = int($value * 0.15);
    }

    $char->setCol('scrap', $char->getCol('scrap') + $value + $bonus);
    $char->setCol('score', $char->getCol('score') + $value + $bonus);

    # ── Irritation from over-budget ──────────────────────────────
    if ($over_soft) {
        $customer->{irritation} += 1;
    }

    # ── Standing ─────────────────────────────────────────────────
    my $fid = $customer->{faction_id};
    my $sales    = $char->getCol('faction_sales') // {};
    my $standing = $char->getCol('standing') // {};

    $sales->{$fid}++;
    my $total_to_faction = $sales->{$fid} // 0;
    my $delta;
    if ($sale_type eq 'match') {
        $delta = $over_soft ? 1 : 2;
    } else {
        $delta = ($sale_type eq 'counter' || $sale_type eq 'stand_pat') ? 1 : 0;
    }
    $delta++ if $item->getCol('has_evolved');
    $delta++ if $total_to_faction >= 2;
    $delta++ if $total_to_faction >= 4;
    $standing->{$fid} += $delta;

    $char->setCol('faction_sales', $sales);
    $char->setCol('standing', $standing);

    my $snubs = $char->getCol('faction_snubs') // {};
    delete $snubs->{$fid};
    $char->setCol('faction_snubs', $snubs);

    my $season = $self->app->active_season;
    if ($season) {
        my $fs = $season->getCol('faction_state') // {};
        $fs->{$fid}->{name}                //= $customer->{faction_name};
        $fs->{$fid}->{influence}            += $value + $bonus;
        $fs->{$fid}->{artifacts_received}++;
        $fs->{$fid}->{daily_intake}++;
        $fs->{$fid}->{days_since_purchase} = 0;
        for my $t (@{ $item->getCol('behaviors') // [] }) {
            $fs->{$fid}->{intake_by_trait}->{$t}++;
        }
        $season->setCol('faction_state', $fs);
        $season->save;
    }

    $self->app->shed->delete($item->getCol('id'));

    $self->_record_disposition($char, $item, $value + $bonus, $delta, $fid) if $season;

    my $pressure = $self->budget_pressure_state($customer);
    my $mood_text = $self->_pick_reaction($customer->{faction_id}, $pressure->{state},
        value => $value, item_id => $item->getCol('artifact_id'),
    );

    my $bonus_msg = $bonus ? sprintf(" Precision hit: +%d bonus scrap!", $bonus) : '';

    $self->_log_event($char, {
        type          => 'sale',
        shed_item_id  => $item->getCol('id'),
        faction_id    => $customer->{faction_id},
        value         => $value + $bonus,
        sale_type     => $sale_type,
        spent_so_far  => $customer->{spent_so_far},
        soft_budget   => $customer->{soft_budget},
        over_budget   => $over_soft ? 1 : 0,
        precision_bonus => $bonus ? 1 : 0,
        narrative     => sprintf("Sale complete: sold to %s for %d scrap.%s",
            $customer->{faction_name}, $value + $bonus, $bonus_msg),
    });

    $self->customer($customer);

    # ── Multi-item: stay in negotiating phase if items remain ────
    my $has_multi = $self->app->can('config') && $self->app->config->{market_multi_item};
    if ($has_multi) {
        my $remaining = $self->app->shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
        if (@$remaining) {
            $customer->{pending_counter} = undef;
            $customer->{last_message} = $mood_text;
            $customer->{last_sale} = {
                value               => $value + $bonus,
                sale_type           => $sale_type,
                precision_bonus     => $bonus,
                pressure_state      => $pressure->{state},
                climate_premium_pct => $customer->{climate_premium_pct} || 0,
            };
            $self->customer($customer);
            $self->save;
            $char->setCol('pending_activity_id', $self->getCol('id'));
            $char->save;
            return {
                view => {
                    ok                  => 1,
                    result              => 'sold_more',
                    value               => $value + $bonus,
                    sale_type           => $sale_type,
                    sold_item_id        => $item->getCol('id'),
                    pressure_state      => $pressure->{state},
                    precision_bonus     => $bonus,
                    climate_premium_pct => $customer->{climate_premium_pct} || 0,
                    irritation      => $customer->{irritation},
                    message         => $mood_text,
                    player          => $self->_player_snapshot($char),
                },
            };
        }
    }

    # ── End visit (single-item mode or no items left) ─────────────
    $char->setCol('result', {
        outcome      => 'sold',
        icon         => 'SCRAP',
        outcome_text => 'Sold!',
        value        => $value + $bonus,
        message      => sprintf('Sold to %s for %d scrap.', $customer->{faction_name}, $value + $bonus),
        item_name    => $item->getCol('artifact_id'),
    });
    $char->setCol('current_view', 'result');
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    return {
        view => {
            ok                  => 1,
            result              => 'sold',
            value               => $value + $bonus,
            sale_type           => $sale_type,
            sold_item_id        => $item->getCol('id'),
            pressure_state      => $pressure->{state},
            precision_bonus     => $bonus,
            climate_premium_pct => $customer->{climate_premium_pct} || 0,
            player          => $self->_player_snapshot($char),
        },
    };
}

sub _record_disposition ($self, $char, $item, $value, $delta, $fid) {
    my $season = $self->app->active_season or return;
    my $rec = $self->app->disposition->create(
        season_id       => $season->getCol('id'),
        player_id       => $char->getCol('account_id'),
        faction_id      => $fid,
        season_day      => $season->getCol('day'),
        value_awarded   => $value,
        artifact_snapshot => {
            artifact_id    => $item->getCol('artifact_id'),
            original_value => $item->getCol('original_value'),
            decayed_value  => $item->getCol('decayed_value'),
            condition      => $item->getCol('condition'),
            days_in_shed   => $item->getCol('days_in_shed'),
            instability    => $item->getCol('instability'),
            stage          => $item->getCol('stage'),
            push_count     => $item->getCol('push_count'),
            has_evolved    => $item->getCol('has_evolved'),
            behaviors      => $item->getCol('behaviors'),
        },
        standing_delta  => $delta,
        influence_delta => $value,
        narrative_hooks => {},
    );
    $rec->save;
}

sub _player_snapshot ($self, $char) {
    return {
        action_points => $char->getCol('action_points'),
        scrap         => $char->getCol('scrap'),
        score         => $char->getCol('score'),
    };
}

1;
