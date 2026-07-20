package MagicMountain::Bot::PressurePolicy;
use Mojo::Base '-base', '-signatures';

sub decide ($self, $context) {
    my $agg = $context->{aggressiveness} // 0.20;
    return if rand() > $agg;

    my $my_score = $context->{my_score} // 0;
    my $my_factions = $context->{my_factions} // [];
    return unless @$my_factions;

    my $rivals = $context->{rivals} // [];
    my %already_on = map { $_->{target_id} . '|' . $_->{faction_id} => 1 }
        @{ $context->{pressures_from_bot} // [] };

    my @candidates;
    for my $rival (@$rivals) {
        next unless ($rival->{score} // 0) > $my_score;

        my $rival_factions = $rival->{pressable_factions} // [];
        my @shared = grep { my $f = $_; grep { $_ eq $f } @$rival_factions } @$my_factions;
        next unless @shared;

        for my $fid (@shared) {
            next if $already_on{ $rival->{id} . '|' . $fid };

            my $stack = $rival->{stack_counts}{$fid} // 0;
            my $max_stack = $context->{pvp_max_stack} // 3;
            next if $stack >= $max_stack;

            my $gap = $rival->{score} - $my_score;
            my $weight = 1.0 + ($gap > 0 ? 0.5 : 0);
            $weight = 1.5 if $weight > 1.5;
            push @candidates, { id => $rival->{id}, faction_id => $fid, weight => $weight };
        }
    }
    return unless @candidates;

    my $total = 0;
    $total += $_->{weight} for @candidates;
    my $roll = rand($total);
    my $cum = 0;
    for my $c (@candidates) {
        $cum += $c->{weight};
        if ($roll < $cum) {
            my $scrap = $context->{my_scrap} // 0;
            my $costs = $context->{pvp_costs} // {};
            my @effects;
            for my $e (qw(spoil_lead outbid corner_market)) {
                my $cost = $costs->{$e} // 50;
                push @effects, $e if $scrap >= $cost;
            }
            return unless @effects;

            @effects = sort { ($costs->{$a} // 50) <=> ($costs->{$b} // 50) } @effects;

            return {
                target_id   => $c->{id},
                faction_id  => $c->{faction_id},
                effect_type => $effects[ int(rand(scalar @effects)) ],
            };
        }
    }
    return;
}

1;
