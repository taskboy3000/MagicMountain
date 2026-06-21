package MagicMountain::Activity::MarketVisit;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

# ── Transition table ────────────────────────────────────────────────

has transitions => sub {
    { idle => ['begin'], negotiating => ['offer', 'send_away'] }
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

sub _random_faction ($self) {
    my $factions = $self->_factions;
    return $factions->[ int(rand(scalar @$factions)) ];
}

sub _weighted_faction ($self, $char) {
    my $factions = $self->_factions;
    my $standing = $char->getCol('standing') // {};

    my $total = 0;
    my @weights;
    for my $f (@$factions) {
        my $w = 1.0 + (($standing->{$f->{id}} // 0) * 0.5);
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

sub _pick_behaviors ($self, $faction) {
    my $interests = $faction->{interests} // [];
    my $count = 1 + int(rand(scalar @$interests > 1 ? 3 : 1));
    $count = scalar @$interests if $count > scalar @$interests;
    my @pool = @$interests;
    my @picked;
    for (1 .. $count) {
        last unless @pool;
        my $idx = int(rand(scalar @pool));
        push @picked, splice(@pool, $idx, 1);
    }
    return \@picked;
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

    my $faction = $self->_weighted_faction($char);
    my $standing = $char->getCol('standing') // {};
    my $mult_bonus = ($standing->{$faction->{id}} // 0) * 0.05;
    my $customer = {
        faction_id          => $faction->{id},
        faction_name        => $faction->{name},
        desired_behaviors   => $self->_pick_behaviors($faction),
        base_multiplier     => ($faction->{base_multiplier} // 1.0) + $mult_bonus,
        offer_value         => undef,
        irritation          => 0,
        irritation_threshold => 5,
    };

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

    return {
        view => {
            ok       => 1,
            result   => 'negotiating',
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

    my $decayed  = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
    my $offer_value;

    if ($intersect) {
        $offer_value = int($decayed * ($customer->{base_multiplier} // 1.0) * 1.2);
        $self->_log_event($char, {
            type          => 'offer',
            shed_item_id  => $shed_item_id,
            faction_id    => $customer->{faction_id},
            match         => 1,
            offered_value => $offer_value,
            accepted      => 1,
            narrative     => sprintf("%s offers %d scrap for the item. Match!",
                $customer->{faction_name}, $offer_value),
        });
        return $self->_do_sale($char, $item, $offer_value, 1);
    } else {
        $offer_value = int($decayed * ($customer->{base_multiplier} // 1.0) * 0.5);
        $customer->{irritation}++;

        if ($customer->{irritation} >= $customer->{irritation_threshold}) {
            $self->_log_event($char, {
                type          => 'offer',
                shed_item_id  => $shed_item_id,
                faction_id    => $customer->{faction_id},
                match         => 0,
                offered_value => $offer_value,
                accepted      => 0,
                irritation    => $customer->{irritation},
                narrative     => sprintf("%s has had enough. They storm off.",
                    $customer->{faction_name}),
            });
            $self->phase('idle');
            $self->customer(undef);
            $self->delete;
            $char->setCol('pending_activity_id', undef);
            $char->save;
            return {
                view => {
                    ok      => 1,
                    result  => 'customer_left',
                    message => sprintf("%s storms off in frustration.", $customer->{faction_name}),
                    player  => $self->_player_snapshot($char),
                },
            };
        }

        $self->_log_event($char, {
            type          => 'offer',
            shed_item_id  => $shed_item_id,
            faction_id    => $customer->{faction_id},
            match         => 0,
            offered_value => $offer_value,
            accepted      => 0,
            irritation    => $customer->{irritation},
            narrative     => sprintf("%s offers only %d scrap. No match (irritation %d/%d).",
                $customer->{faction_name}, $offer_value,
                $customer->{irritation}, $customer->{irritation_threshold}),
        });
        $self->customer($customer);
        $self->save;
        return {
            view => {
                ok        => 1,
                result    => 'no_match',
                irritation => $customer->{irritation},
                max_irritation => $customer->{irritation_threshold},
                message   => sprintf("%s frowns but gestures for you to try another item.",
                    $customer->{faction_name}),
                player    => $self->_player_snapshot($char),
            },
        };
    }
}

# ── send_away ─────────────────────────────────────────────────────────

sub send_away ($self, $char, %params) {
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

sub _do_sale ($self, $char, $item, $value, $was_match) {
    $char->setCol('scrap', $char->getCol('scrap') + $value);
    $char->setCol('score', $char->getCol('score') + $value);

    my $fid = $self->customer->{faction_id};
    my $sales    = $char->getCol('faction_sales') // {};
    my $standing = $char->getCol('standing') // {};

    $sales->{$fid}++;
    my $delta = $was_match ? 2 : 1;
    $delta++ if $item->getCol('has_evolved');
    $standing->{$fid} += $delta;

    $char->setCol('faction_sales', $sales);
    $char->setCol('standing', $standing);

    my $season = $self->app->active_season;
    if ($season) {
        my $fs = $season->getCol('faction_state') // {};
        $fs->{$fid}->{influence}          += $value;
        $fs->{$fid}->{artifacts_received}++;
        for my $t (@{ $item->getCol('behaviors') // [] }) {
            $fs->{$fid}->{intake_by_trait}->{$t}++;
        }
        $season->setCol('faction_state', $fs);
        $season->save;
    }

    $self->app->shed->delete($item->getCol('id'));
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    $self->_log_event($char, {
        type         => 'sale',
        shed_item_id => $item->getCol('id'),
        faction_id   => $self->customer->{faction_id},
        value        => $value,
        narrative    => sprintf("Sale complete: sold to %s for %d scrap.",
            $self->customer->{faction_name}, $value),
    });

    return {
        view => {
            ok      => 1,
            result  => 'sold',
            value   => $value,
            player  => $self->_player_snapshot($char),
        },
    };
}

sub _player_snapshot ($self, $char) {
    return {
        action_points => $char->getCol('action_points'),
        scrap         => $char->getCol('scrap'),
        score         => $char->getCol('score'),
    };
}

1;
