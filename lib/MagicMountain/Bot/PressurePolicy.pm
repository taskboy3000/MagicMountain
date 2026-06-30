package MagicMountain::Bot::PressurePolicy;
use Mojo::Base '-base', '-signatures';

sub decide ($self, $bot_char, $context) {
    my $app    = $context->{app};
    my $season = $context->{season};

    return undef unless $app->config->{pvp_enabled};

    my $profile_pct = $context->{profiles}
        ? ($context->{profiles}{ $bot_char->getCol('id') }{pvp_aggressiveness} // undef)
        : undef;
    my $agg = defined $profile_pct
        ? $profile_pct
        : ($app->config->{pvp_bot_aggressiveness} // 0.20);
    return undef if rand() > $agg;

    my $my_score = $bot_char->getCol('score') // 0;
    my $my_sales = $bot_char->getCol('faction_sales') // {};
    my @my_factions = grep { ($my_sales->{$_} // 0) >= 1 } keys %$my_sales;
    return undef unless @my_factions;

    my $chars = $context->{characters} || [];
    my %already_on;
    for my $p (@{ $context->{pressures_from_bot} // [] }) {
        next unless $p->{target_id} && $p->{faction_id};
        $already_on{ $p->{target_id} . '|' . $p->{faction_id} } = 1;
    }

    my @candidates;
    for my $rival (@$chars) {
        next if $rival->getCol('id') eq $bot_char->getCol('id');
        next unless ($rival->getCol('season_id') // '') eq $season->getCol('id');
        next unless ($rival->getCol('score') // 0) > $my_score;

        my $rival_sales = $rival->getCol('faction_sales') // {};
        my @shared = grep { ($my_sales->{$_} // 0) >= 1 && ($rival_sales->{$_} // 0) >= 1 } @my_factions;
        next unless @shared;

        for my $fid (@shared) {
            next if $already_on{ $rival->getCol('id') . '|' . $fid };

            my $stack = $app->pressures->count_active_on(
                $rival->getCol('id'), $fid,
                $app->config->{pvp_pressure_max_age_days});
            next if $stack >= ($app->config->{pvp_max_stack} // 3);

            my $gap = ($rival->getCol('score') // 0) - $my_score;
            my $weight = 1.0 + ($gap > 0 ? 0.5 : 0);
            $weight = 1.5 if $weight > 1.5;
            push @candidates, { row => $rival, faction_id => $fid, weight => $weight };
        }
    }
    return undef unless @candidates;

    my $total = 0;
    $total += $_->{weight} for @candidates;
    my $roll = rand($total);
    my $cum = 0;
    for my $c (@candidates) {
        $cum += $c->{weight};
        if ($roll < $cum) {
            my $scrap = $bot_char->getCol('scrap') // 0;
            my @effects;
            for my $e (qw(spoil_lead outbid corner_market)) {
                my $cost = $app->config->{"pvp_cost_$e"} // 50;
                push @effects, $e if $scrap >= $cost;
            }
            return undef unless @effects;

            # Prefer cheaper effects (spoil_lead < outbid < corner_market).
            @effects = sort {
                ($app->config->{"pvp_cost_$a"} // 50) <=> ($app->config->{"pvp_cost_$b"} // 50)
            } @effects;

            return {
                target_id   => $c->{row}->getCol('id'),
                faction_id  => $c->{faction_id},
                effect_type => $effects[ int(rand(scalar @effects)) ],
            };
        }
    }
    return undef;
}

1;
