package MagicMountain::Activity::Pawn;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Activity', '-signatures';

has transitions => sub {
    { idle => ['offer'], result => ['dismiss', 'offer_next'] }
};

has _activity_type => sub { 'pawn' };

sub create ($self, %params) {
    $params{type}  //= 'pawn';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}

sub _pick_flavor ($self, $outcome) {
    my $data = $self->content_data or return;
    my $lines = $data->{$outcome} or return;
    return $lines->[int(rand(scalar @$lines))];
}

sub offer ($self, $char, %params) {
    my $shed_item_id = $params{shed_item_id} or die "shed_item_id is required";
    die "AP exhausted" unless ($char->getCol('action_points') // 0) >= 1;

    my $item = $self->app->shed->get($shed_item_id);
    die "shed item not found" unless $item;
    die "shed item belongs to another character"
        unless $item->getCol('char_id') eq $char->getCol('id');
    
    my $calc = $self->app->pawn_calculator;
    my $lookup = $calc->banned_trait_lookup;
    my $behaviors = $item->getCol('behaviors') // [];
    my $has_banned = grep { $lookup->{$_} } @$behaviors;
    die "item has no banned traits" unless $has_banned;

    my $decayed = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
    my $premium_mult = $calc->premium_multiplier;
    my $seizure_chance = $calc->seizure_chance($decayed);
    $seizure_chance = $calc->apply_smuggling($char, $seizure_chance);
    my $offer_value = int($decayed * $premium_mult);

    $self->save;
    my $id = $self->getCol('id');
    my $newActionPoints = $char->getCol('action_points') - 1;
    $char->setCol('action_points', $newActionPoints);
    $char->setCol('pending_activity_id', $id);

    my $seized = 0;
    if (rand() < $seizure_chance) {
        my $smuggle = $char->getCol('skill_smuggling') // 0;
        my $reroll_used = $char->getCol('smuggle_reroll_used') // 0;
        if ($smuggle >= 4 && !$reroll_used) {
            $char->setCol('smuggle_reroll_used', 1);
            $seized = 1 if rand() < $seizure_chance;
        } else {
            $seized = 1;
        }
    }

    my $season = $self->app->active_season;

    if ($seized) {
        if ($self->app->can('brokers_cache')) {
            $self->app->brokers_cache->log_entry(
                season_id     => $season ? $season->getCol('id') : undef,
                player_id     => $char->getCol('account_id'),
                artifact_id   => $item->getCol('artifact_id'),
                decayed_value => $decayed,
                behaviors     => $behaviors,
                char_name     => $char->getCol('name'),
            );
        }

        $self->app->shed->delete($shed_item_id);

        my $narrative = $self->_pick_flavor('seizure')
            // "The authorities raid the pawn shop and seize your goods!";

        $self->_log_event($char, {
            type           => 'pawn_seizure',
            shed_item_id   => $shed_item_id,
            artifact_id    => $item->getCol('artifact_id'),
            value          => $decayed,
            seizure_chance => $seizure_chance,
            narrative      => $narrative,
        });

        $char->setCol('result', {
            outcome      => 'seized',
            icon         => 'ALERT',
            outcome_text => 'SEIZED!',
            message      => $narrative,
            item_name    => $item->getCol('artifact_id'),
        });
        $char->setCol('current_view', 'pawn');
        $self->phase('result');
        $self->customer({ outcome => 'seized', value => 0, premium_mult => $premium_mult, seizure_chance => $seizure_chance });
        $self->save;
        $char->save;

        return {
            view => {
                ok           => 1,
                result       => 'seized',
                value        => 0,
                premium_mult => $premium_mult,
                message      => $narrative,
                player       => $self->_player_snapshot($char),
            },
        };
    }

    $char->setCol('scrap', $char->getCol('scrap') + $offer_value);
    $char->setCol('score', $char->getCol('score') + $offer_value);
    $self->app->shed->delete($shed_item_id);

    my $narrative = $self->_pick_flavor('sale')
        // sprintf("The broker counts out %d scrap and hands it over.", $offer_value);

    $self->_log_event($char, {
        type           => 'pawn_sale',
        shed_item_id   => $shed_item_id,
        artifact_id    => $item->getCol('artifact_id'),
        value          => $offer_value,
        premium_mult   => $premium_mult,
        seizure_chance => $seizure_chance,
        narrative      => $narrative,
    });

    $char->setCol('result', {
        outcome      => 'sold',
        icon         => 'SCRAP',
        outcome_text => 'SOLD',
        value        => $offer_value,
        premium_mult => $premium_mult,
        message      => $narrative,
        item_name    => $item->getCol('artifact_id'),
    });
    $char->setCol('current_view', 'pawn');
    $self->phase('result');
    $self->customer({ outcome => 'sold', value => $offer_value, premium_mult => $premium_mult, seizure_chance => $seizure_chance });
    $self->save;
    $char->save;

    return {
        view => {
            ok           => 1,
            result       => 'sold',
            value        => $offer_value,
            premium_mult => $premium_mult,
            message      => $narrative,
            player       => $self->_player_snapshot($char),
        },
    };
}

sub dismiss ($self, $char, %params) {
    $self->delete;
    $char->setCol('pending_activity_id', undef);
    $char->setCol('current_view', 'home');
    $char->setCol('result', undef);
    $char->save;

    $self->_log_event($char, {
        type      => 'pawn_dismiss',
        narrative => sprintf("%s leaves the pawn shop.", $char->getCol('name') // 'unknown'),
    });

    return {
        view => {
            ok      => 1,
            result  => 'dismissed',
            message => 'You leave the pawn shop.',
            player  => $self->_player_snapshot($char),
        },
    };
}

sub offer_next ($self, $char, %params) {
    $self->phase('idle');
    $self->customer(undef);
    $self->save;

    $char->setCol('result', undef);
    $char->setCol('current_view', 'pawn');
    $char->save;

    return {
        view => {
            ok      => 1,
            result  => 'offer_next',
            message => 'Select another item to pawn.',
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
