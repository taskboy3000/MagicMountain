package MagicMountain::Service::PvP;
use Mojo::Base '-base', '-signatures';
use YAML::XS qw(LoadFile);
use List::Util 'shuffle';

has app => sub { die "app is required" };

has _reactions => sub { undef };

has effect_types => sub { +{
    corner_market => { cost_key => 'pvp_cost_corner_market', moment => 'on_sale' },
    spoil_lead    => { cost_key => 'pvp_cost_spoil_lead',    moment => 'on_begin' },
    outbid        => { cost_key => 'pvp_cost_outbid',         moment => 'on_begin' },
} };

sub _cost ($self, $effect_type) {
    my $key = $self->effect_types->{$effect_type}{cost_key} // 'pvp_cost_corner_market';
    return $self->app->config->{$key} // 50;
}

sub apply_pressure ($self, $attacker, $target_id, $faction_id, $effect_type) {
    return { ok => 0, error => 'pvp disabled' }
        unless $self->app->config->{pvp_enabled};

    return { ok => 0, error => 'unknown effect type' }
        unless $self->effect_types->{$effect_type};

    return { ok => 0, error => 'cannot press yourself' }
        if $target_id eq $attacker->getCol('id');

    $self->app->characters->load;
    my $target = $self->app->characters->get($target_id);
    return { ok => 0, error => 'target not found' } unless $target;

    my $season = $self->app->active_season or return { ok => 0, error => 'no active season' };

    return { ok => 0, error => 'target not in same season' }
        unless $target->getCol('season_id') eq $season->getCol('id');

    my $attacker_rank = $self->app->season_manager->rank_of($attacker);
    my $target_rank   = $self->app->season_manager->rank_of($target);
    return { ok => 0, error => 'can only press rivals ranked above you' }
        unless defined $attacker_rank && defined $target_rank && $target_rank < $attacker_rank;

    my $target_sales = $target->getCol('faction_sales') // {};
    return { ok => 0, error => 'target has no lead with that faction' }
        unless ($target_sales->{$faction_id} // 0) >= 1;

    my $stack = $self->app->pressures->count_active_on($target_id, $faction_id,
        $self->app->config->{pvp_pressure_max_age_days});
    return { ok => 0, error => 'pressure stack limit reached' }
        if $stack >= ($self->app->config->{pvp_max_stack} // 3);

    my $cost = $self->_cost($effect_type);
    return { ok => 0, error => 'not enough scrap' }
        if ($attacker->getCol('scrap') // 0) < $cost;

    $attacker->setCol('scrap', $attacker->getCol('scrap') - $cost);
    $attacker->save;

    if ($effect_type eq 'spoil_lead') {
        my $loss = $self->app->config->{pvp_splash_standing_loss} // 1;
        my $s = $attacker->getCol('standing') // {};
        $s->{$faction_id} = ($s->{$faction_id} // 0) - $loss;
        $attacker->setCol('standing', $s);
        $attacker->save;
    }

    my $pressure = $self->app->pressures->create(
        attacker_id         => $attacker->getCol('id'),
        target_id           => $target_id,
        faction_id          => $faction_id,
        effect_type         => $effect_type,
        attacker_consumed   => ($effect_type eq 'spoil_lead' ? 1 : 0),
    );
    $pressure->save;

    $self->app->audit_log->log('pressure_applied',
        attacker_id   => $attacker->getCol('id'),
        attacker_name => $attacker->getCol('name'),
        target_id     => $target_id,
        target_name   => $target->getCol('name'),
        faction_id    => $faction_id,
        effect_type   => $effect_type,
        cost          => $cost,
    );

    return {
        ok     => 1,
        result => 'pressure_applied',
        cost   => $cost,
        pressure => {
            id          => $pressure->getCol('id'),
            effect_type => $effect_type,
            faction_id  => $faction_id,
            target_id   => $target_id,
            cost        => $cost,
        },
    };
}

sub _consume ($self, $char_id, $faction_id, $moment, $age_key) {
    my $aged = $self->app->config->{pvp_pressure_max_age_days};
    my $active = $age_key eq 'target_id'
        ? $self->app->pressures->find_active_for_target($char_id, $faction_id, $aged)
        : $self->app->pressures->find_active_for_attacker($char_id, $faction_id, $aged);

    my $effects = {};
    for my $p (sort { ($a->getCol('createdAt') // 0) <=> ($b->getCol('createdAt') // 0) } @$active) {
        my $type = $p->getCol('effect_type');
        my $info = $self->effect_types->{$type} or next;
        next unless $info->{moment} eq $moment;

        if ($type eq 'spoil_lead') {
            my $threshold = $self->app->config->{market_irritation_threshold} // 4;
            $effects->{irritation_floor} = $threshold - 1;
        } elsif ($type eq 'outbid') {
            $effects->{budget_ratio} = $self->app->config->{pvp_splash_budget_ratio} // 0.80;
        } elsif ($type eq 'corner_market') {
            $effects->{saturation_floor} = $self->app->config->{pvp_splash_saturation_floor} // 0.50;
        }

        if ($age_key eq 'target_id') {
            $p->setCol('target_consumed', 1);
        } else {
            $p->setCol('attacker_consumed', 1);
        }
        $p->save;

        $self->app->audit_log->log(
            $age_key eq 'target_id' ? 'pressure_fired_target' : 'pressure_fired_splashback',
            attacker_id => $p->getCol('attacker_id'),
            target_id   => $p->getCol('target_id'),
            faction_id  => $p->getCol('faction_id'),
            effect_type => $type,
        );

        # Lazy-delete if both consumed.
        if ($p->getCol('target_consumed') && $p->getCol('attacker_consumed')) {
            $self->app->pressures->delete($p->getCol('id'));
        }

        # Only consume one pressure per visit/sale (FIFO).
        last;
    }

    return $effects;
}

sub consume_target_effects ($self, $char_id, $faction_id, $moment) {
    return $self->_consume($char_id, $faction_id, $moment, 'target_id');
}

sub consume_attacker_splashbacks ($self, $char_id, $faction_id, $moment) {
    return $self->_consume($char_id, $faction_id, $moment, 'attacker_id');
}

sub reaction_text ($self, $effect_type, $faction_id, $side) {
    my $reactions = $self->_reactions;
    if (!defined $reactions) {
        my $file = $self->app->home . '/content/flavor/pressure_reactions.yml';
        $reactions = -e $file ? LoadFile($file) : {};
        $self->_reactions($reactions);
    }

    my $pool = $reactions->{$side}{$effect_type}{$faction_id}
            // $reactions->{$side}{$effect_type}{_generic}
            // [];
    return @$pool > 0 ? $pool->[int(rand(@$pool))] : 'Your rival has been busy.';
}

sub build_view ($self, $char, %params) {
    my $app = $self->app;
    return { disabled => 1 } unless $app->config->{pvp_enabled};

    my $season = $app->active_season or return { disabled => 1, reason => 'no_season' };

    $app->characters->load;
    $app->pressures->load;

    my $chars = $app->characters->find(
        sub { $_[0]->{season_id} eq $season->getCol('id') }
    );
    my $my_score = $char->getCol('score') // 0;
    my @rivals = sort { ($b->getCol('score') // 0) <=> ($a->getCol('score') // 0) }
                 grep { ($_->getCol('score') // 0) > $my_score } @$chars;

    my @rivals_view = map {
        my $sales = $_->getCol('faction_sales') // {};
        { id               => $_->getCol('id'),
          name             => $_->getCol('name'),
          is_bot           => ($_->getCol('is_bot') // 0) ? 1 : 0,
          score            => $_->getCol('score'),
          pressable_factions => [ grep { ($sales->{$_} // 0) >= 1 } keys %$sales ] }
    } @rivals;

    my $aged = $app->config->{pvp_pressure_max_age_days};
    my @active_target = @{ $app->pressures->find_active_for_target(
        $char->getCol('id'), undef, $aged) };
    # "Your pressure" = pressures where target_consumed is
    # still 0 (the rival hasn't been hit yet), regardless of
    # attacker_consumed (spoil_lead marks attacker_consumed=1
    # at creation since its splashback fires immediately).
    my @active_attacker = grep {
        !$_->getCol('target_consumed')
    } @{ $app->pressures->find(
        sub { $_[0]->{attacker_id} eq $char->getCol('id')
              && !$_[0]->{target_consumed} }
    ) };

    return {
        rivals          => \@rivals_view,
        active_target   => [ map { _pressure_view($_) } @active_target ],
        active_attacker => [ map { _pressure_view($_) } @active_attacker ],
        scrap           => $char->getCol('scrap'),
        actions         => $self->_rival_actions($char, \@rivals_view, $params{apply_url}),
    };
}

sub _rival_actions ($self, $char, $rivals_view, $apply_url) {
    my $cfg   = $self->app->config;
    my $scrap = $char->getCol('scrap') // 0;
    my %cost  = (
        corner_market => $cfg->{pvp_cost_corner_market} // 50,
        spoil_lead    => $cfg->{pvp_cost_spoil_lead}    // 30,
        outbid        => $cfg->{pvp_cost_outbid}         // 75,
    );
    my %label = (
        corner_market => 'Corner the Market',
        spoil_lead    => 'Spoil the Lead',
        outbid        => 'Outbid',
    );

    my @actions;
    for my $r (@$rivals_view) {
        for my $fid (@{ $r->{pressable_factions} // [] }) {
            for my $effect (qw(corner_market spoil_lead outbid)) {
                my $c = $cost{$effect};
                push @actions, {
                    label => "$label{$effect} ($r->{name}, $fid) \x{2014} $c scrap",
                    attrs => {
                        'data-action-url'  => $apply_url,
                        'data-method'      => 'POST',
                        'data-target-id'   => $r->{id},
                        'data-faction-id'  => $fid,
                        'data-effect-type' => $effect,
                        class              => 'mm-btn mm-btn-pvp',
                        confirm            => "Spend $c scrap to press $r->{name}'s $fid lead?",
                        ($scrap < $c ? (disabled => undef) : ()),
                    },
                };
            }
        }
    }
    return \@actions;
}

sub _pressure_view ($p) {
    return {
        id          => $p->getCol('id'),
        effect_type => $p->getCol('effect_type'),
        faction_id  => $p->getCol('faction_id'),
        attacker_id => $p->getCol('attacker_id'),
        target_id   => $p->getCol('target_id'),
        target_consumed   => $p->getCol('target_consumed'),
        attacker_consumed => $p->getCol('attacker_consumed'),
    };
}

1;
