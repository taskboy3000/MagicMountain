package MagicMountain::Activity::BlackMarket;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

has transitions => sub {
    { idle => ['begin'], negotiating => ['accept', 'withdraw'] }
};

sub create ($self, %params) {
    $params{type}  //= 'black_market';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}

sub _premium_multiplier ($self, $value) {
    my $mult = 1.2 + ($value / 100) * 0.4;
    return $mult > 2.5 ? 2.5 : $mult;
}

sub _base_seizure_chance ($self, $value) {
    my $chance = 0.05 + ($value / 200) * 0.30;
    return $chance > 0.35 ? 0.35 : $chance;
}

sub _pick_flavor ($self, $outcome) {
    my $data = $self->content_data or return;
    my $lines = $data->{$outcome} or return;
    return $lines->[int(rand(scalar @$lines))];
}

sub begin ($self, $char, %params) {
    my $shed_item_id = $params{shed_item_id} or die "shed_item_id is required";
    die "AP exhausted" unless ($char->getCol('action_points') // 0) >= 1;

    # Accept climate from params (avoids mtime cache staleness when same-tick saves
    # prevent active_season from seeing freshly-written climate data). Fall back to
    # active_season for non-controller callers (bots, direct dispatch, tests).
    my $climate = $params{faction_climate};
    if (!$climate || !keys %$climate) {
        my $season = $self->app->active_season or die "no active season";
        $climate = $season->getCol('faction_climate') // {};
    }
    my @banned = @{ $climate->{banned_traits} // [] };
    die "no banned traits active" unless @banned;

    my $item = $self->app->shed->get($shed_item_id);
    die "shed item not found" unless $item;
    die "shed item belongs to another character"
        unless $item->getCol('char_id') eq $char->getCol('id');

    my $behaviors = $item->getCol('behaviors') // [];
    my $has_banned = grep { my $b = $_; grep { $_ eq $b } @banned } @$behaviors;
    die "item has no banned traits" unless $has_banned;

    my $decayed = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
    my $premium_mult = $self->_premium_multiplier($decayed);
    my $seizure_chance = $self->_base_seizure_chance($decayed);

    # SMUGGLING skill reduces seizure chance
    my $smuggle = $char->getCol('skill_smuggling') // 0;
    $seizure_chance -= 0.05 * $smuggle;
    $seizure_chance = 0.02 if $seizure_chance < 0.02;

    my $offer_value = int($decayed * $premium_mult);

    my $arrival_text = $self->_pick_flavor('arrival')
        // "A broker has signaled interest in your restricted goods.";

    $char->setCol('action_points', $char->getCol('action_points') - 1);
    $char->setCol('black_market_opportunity_offered_today', 1);

    $self->customer({
        item_id        => $shed_item_id,
        offer_value    => $offer_value,
        seizure_chance => $seizure_chance,
        premium_mult   => $premium_mult,
        artifact_id    => $item->getCol('artifact_id'),
        arrival_text   => $arrival_text,
    });
    $self->phase('negotiating');
    $self->save;  # save FIRST so ID is generated
    $char->setCol('pending_activity_id', $self->getCol('id'));
    $char->save;

    $self->_log_event($char, {
        type         => 'black_market_begin',
        shed_item_id => $shed_item_id,
        artifact_id  => $item->getCol('artifact_id'),
        offer_value  => $offer_value,
        seizure_chance => $seizure_chance,
        premium_mult => $premium_mult,
        narrative    => sprintf("%s enters the black market with %s (value=%d, premium=%.2fx, seizure=%.0f%%).",
            $char->getCol('name') // 'unknown',
            $item->getCol('artifact_id') // '?',
            $decayed, $premium_mult, $seizure_chance * 100),
    });

    return {
        view => {
            ok             => 1,
            result         => 'broker_arrival',
            offer_value    => $offer_value,
            seizure_chance => $seizure_chance,
            premium_mult   => $premium_mult,
            artifact_id    => $item->getCol('artifact_id'),
            message        => $arrival_text,
            player         => $self->_player_snapshot($char),
        },
    };
}

sub accept ($self, $char, %params) {
    my $deal = $self->customer or die "no active deal";
    my $item_id = $deal->{item_id} or die "no item in deal";
    my $seizure_chance = $deal->{seizure_chance} // 0;
    my $offer_value = $deal->{offer_value} // 0;

    my $item = $self->app->shed->get($item_id);
    die "shed item not found" unless $item;

    my $smuggle = $char->getCol('skill_smuggling') // 0;
    my $reroll_used = $char->getCol('smuggle_reroll_used') // 0;
    my $has_reroll = ($smuggle >= 4 && !$reroll_used);

    my $seized = 0;
    if (rand() < $seizure_chance) {
        if ($has_reroll) {
            # Level 4 reroll: try once more
            $char->setCol('smuggle_reroll_used', 1);
            if (rand() < $seizure_chance) {
                $seized = 1;
            }
        } else {
            $seized = 1;
        }
    }

    # Record disposition on every black market transaction (sale or seizure)
    my $season = $self->app->active_season;
    if ($season && $self->app->can('disposition')) {
        $self->app->disposition->create(
            season_id       => $season->getCol('id'),
            player_id       => $char->getCol('account_id'),
            faction_id      => 'black_market',
            season_day      => $season->getCol('day'),
            value_awarded   => $seized ? 0 : $offer_value,
            artifact_snapshot => {
                artifact_id    => $item->getCol('artifact_id'),
                original_value => $item->getCol('original_value'),
                decayed_value  => $item->getCol('decayed_value'),
                condition      => $item->getCol('condition'),
                instability    => $item->getCol('instability'),
                stage          => $item->getCol('stage'),
                push_count     => $item->getCol('push_count'),
                has_evolved    => $item->getCol('has_evolved'),
                behaviors      => $item->getCol('behaviors'),
            },
            standing_delta  => 0,
            influence_delta => $seized ? 0 : $offer_value,
            narrative_hooks => { outcome => $seized ? 'seized' : 'sold' },
        )->save;
    }

    if ($seized) {
        # Log to BrokersCache for future recovery
        if ($self->app->can('brokers_cache')) {
            $self->app->brokers_cache->log_entry(
                season_id    => $season ? $season->getCol('id') : undef,
                player_id    => $char->getCol('account_id'),
                artifact_id  => $item->getCol('artifact_id'),
                decayed_value => $item->getCol('decayed_value') // 0,
                behaviors    => $item->getCol('behaviors') // [],
                char_name    => $char->getCol('name'),
            );
        }

        $self->app->shed->delete($item->getCol('id'));

        my $narrative = $self->_pick_flavor('seizure')
            // "Your shipment was intercepted. The broker's channel has gone dark.";

        $self->_log_event($char, {
            type          => 'black_market_seizure',
            shed_item_id  => $item_id,
            artifact_id   => $item->getCol('artifact_id'),
            offer_value   => $offer_value,
            seizure_chance => $seizure_chance,
            narrative     => $narrative,
        });

        $char->setCol('result', {
            outcome      => 'seized',
            icon         => 'ALERT',
            outcome_text => 'SHIPMENT SEIZED',
            message      => $narrative,
            item_name    => $item->getCol('artifact_id'),
        });
        $char->setCol('current_view', 'result');

        $self->delete;
        $char->setCol('pending_activity_id', undef);
        $char->save;

        return {
            view => {
                ok       => 1,
                result   => 'seized',
                message  => $narrative,
                player   => $self->_player_snapshot($char),
            },
        };
    }

    # Success: award scrap + score
    $char->setCol('scrap', $char->getCol('scrap') + $offer_value);
    $char->setCol('score', $char->getCol('score') + $offer_value);
    $self->app->shed->delete($item->getCol('id'));

    my $narrative = $self->_pick_flavor('match')
        // "The transaction clears. No record. No trail.";

    $self->_log_event($char, {
        type          => 'black_market_sale',
        shed_item_id  => $item_id,
        artifact_id   => $item->getCol('artifact_id'),
        offer_value   => $offer_value,
        seizure_chance => $seizure_chance,
        premium_mult  => $deal->{premium_mult},
        narrative     => $narrative,
    });

    $char->setCol('result', {
        outcome      => 'sold_black_market',
        icon         => 'SCRAP',
        outcome_text => 'SOLD (BLACK MARKET)',
        value        => $offer_value,
        message      => sprintf('Sold to anonymous broker for %d scrap.', $offer_value),
        item_name    => $item->getCol('artifact_id'),
    });
    $char->setCol('current_view', 'result');

    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    return {
        view => {
            ok       => 1,
            result   => 'sold_black_market',
            value    => $offer_value,
            message  => $narrative,
            player   => $self->_player_snapshot($char),
        },
    };
}

sub withdraw ($self, $char, %params) {
    my $narrative = $self->_pick_flavor('withdraw')
        // "The broker's channel remains open, but idle.";

    $self->_log_event($char, {
        type      => 'black_market_withdraw',
        narrative => sprintf("%s withdraws from black market negotiation.",
            $char->getCol('name') // 'unknown'),
    });

    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->save;

    return {
        view => {
            ok      => 1,
            result  => 'withdrawn',
            message => $narrative,
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
