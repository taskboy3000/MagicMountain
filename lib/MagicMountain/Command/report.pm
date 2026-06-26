package MagicMountain::Command::report;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Model::Transcript;

has description => 'Aggregate transcript stats for tuning analysis.';
has usage => "Usage: $0 report [--transcript FILE] [--player ID]\n"
           . "  --transcript FILE  Transcript path (default data/transcript.jsonl)\n"
           . "  --player ID        Filter to a specific character ID\n";

sub run ($self, @args) {
    my ($transcript_path, $player);
    for (my $i = 0; $i < @args; $i++) {
        if ($args[$i] eq '--transcript' && $i + 1 < @args) { $transcript_path = $args[++$i] }
        if ($args[$i] eq '--player' && $i + 1 < @args) { $player = $args[++$i] }
    }

    my $transcript;
    if ($transcript_path) {
        $transcript = MagicMountain::Model::Transcript->new(file => $transcript_path);
    } else {
        $transcript = $self->app->transcript;
    }

    my @events = @{ $transcript->all_events };
    my (@players, @prospecting, @market, %by_char);
    for my $e (@events) {
        next if $player && $e->{char_id} ne $player;
        next if $e->{type} =~ /^policy_|^sim_|decay_tick|faction_snapshot/;
        push @players, $e->{char_id} unless $by_char{$e->{char_id}}++;
        if ($e->{type} eq 'artifact_start') {
            push @prospecting, { char_id => $e->{char_id}, id => $e->{artifact_id}, pushes => 0, collapse => 0, breakthrough => 0, stop => 0 };
        }
        if ($e->{type} eq 'push') {
            my $a = _current_artifact(\@prospecting, $e->{char_id});
            $a->{pushes}++ if $a;
        }
        if ($e->{type} eq 'collapse') {
            my $a = _current_artifact(\@prospecting, $e->{char_id});
            $a->{collapse} = 1 if $a;
        }
        if ($e->{type} eq 'breakthrough') {
            my $a = _current_artifact(\@prospecting, $e->{char_id});
            $a->{breakthrough} = 1 if $a;
        }
        if ($e->{type} eq 'stop') {
            my $a = _current_artifact(\@prospecting, $e->{char_id});
            $a->{stop} = 1 if $a;
        }
        if ($e->{type} eq 'market_visit') {
            push @market, { char_id => $e->{char_id}, offers => 0, counters => 0, counters_accepted => 0, sales => 0, send_aways => 0, stand_pats => 0, stand_pat_successes => 0, mismatches => 0, irritation_total => 0, mood_events => 0 };
        }
        if ($e->{type} eq 'offer') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{offers}++ if $m;
            $m->{mismatches}++ if $m && !$e->{match};
            $m->{sales}++ if $m && $e->{accepted};
        }
        if ($e->{type} eq 'counter_offer') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{counters}++ if $m;
        }
        if ($e->{type} eq 'accept_counter') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{counters_accepted}++ if $m;
        }
        if ($e->{type} eq 'sale') {
            my $m = _current_market(\@market, $e->{char_id});
            if ($m) {
                $m->{sales}++;
                my $v = $e->{value} // 0;
                my $st = $e->{sale_type} // 'unknown';
                $m->{sale_values}{$st}{min} = $v if !defined($m->{sale_values}{$st}{min}) || $v < $m->{sale_values}{$st}{min};
                $m->{sale_values}{$st}{max} = $v if !defined($m->{sale_values}{$st}{max}) || $v > $m->{sale_values}{$st}{max};
                $m->{sale_values}{$st}{sum} += $v;
                $m->{sale_values}{$st}{n}++;
            }
        }
        if ($e->{type} eq 'send_away') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{send_aways}++ if $m;
        }
        if ($e->{type} eq 'stand_pat') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{stand_pats}++ if $m;
            $m->{stand_pat_successes}++ if $m && $e->{accepted};
        }
        if ($e->{type} eq 'stand_pat_fail') {
            my $m = _current_market(\@market, $e->{char_id});
            $m->{stand_pats}++ if $m;
        }
    }

    my $n = scalar @players;
    printf "Characters: %d\n", $n;

    if (@prospecting) {
        my $total  = scalar @prospecting;
        my $collapsed = scalar grep { $_->{collapse} } @prospecting;
        my $breakthroughs = scalar grep { $_->{breakthrough} } @prospecting;
        my $stopped = scalar grep { $_->{stop} } @prospecting;
        my $total_pushes = 0; $total_pushes += $_->{pushes} for @prospecting;
        printf "\n-- Prospecting ------------------------------\n";
        printf "  Expeditions:      %d\n", $total;
        printf "  Avg pushes/exp:   %.1f\n", $total ? $total_pushes / $total : 0;
        printf "  Collapse rate:    %.1f%%\n", $total ? $collapsed / $total * 100 : 0;
        printf "  Breakthrough rate: %.1f%%\n", $total ? $breakthroughs / $total * 100 : 0;
        printf "  Stop rate:        %.1f%%\n", $total ? $stopped / $total * 100 : 0;
    }

    if (@market) {
        my $visits     = scalar @market;
        my $offers     = 0; $offers += $_->{offers} for @market;
        my $counters   = 0; $counters += $_->{counters} for @market;
        my $ca         = 0; $ca += $_->{counters_accepted} for @market;
        my $sales      = 0; $sales += $_->{sales} for @market;
        my $sa         = 0; $sa += $_->{send_aways} for @market;
        my $sp         = 0; $sp += $_->{stand_pats} for @market;
        my $sp_succ    = 0; $sp_succ += $_->{stand_pat_successes} for @market;
        my $mismatches = 0; $mismatches += $_->{mismatches} for @market;
        printf "\n-- Market -----------------------------------\n";
        printf "  Visits:           %d\n", $visits;
        printf "  Avg offers/visit: %.1f\n", $visits ? $offers / $visits : 0;
        printf "  Counter-offers:   %d (%.1f%% accepted)\n", $counters, $counters ? $ca / $counters * 100 : 0;
        printf "  Send-aways:       %d\n", $sa;
        printf "  Stand-pats:       %d (%.1f%% success)\n", $sp, $sp ? $sp_succ / $sp * 100 : 0;
        printf "  Sales:            %d\n", $sales;

        # Aggregate sale prices across all market visits
        my %agg;
        for my $m (@market) {
            for my $st (keys %{ $m->{sale_values} // {} }) {
                $agg{$st}{min} = $m->{sale_values}{$st}{min} if !defined($agg{$st}{min}) || $m->{sale_values}{$st}{min} < $agg{$st}{min};
                $agg{$st}{max} = $m->{sale_values}{$st}{max} if !defined($agg{$st}{max}) || $m->{sale_values}{$st}{max} > $agg{$st}{max};
                $agg{$st}{sum} += $m->{sale_values}{$st}{sum};
                $agg{$st}{n}   += $m->{sale_values}{$st}{n};
            }
        }
        if (keys %agg) {
            printf "\n  Sale prices by type:\n";
            for my $st (sort keys %agg) {
                my $avg = $agg{$st}{n} ? int($agg{$st}{sum} / $agg{$st}{n}) : 0;
                printf "    %-15s  n=%3d  avg=%3d  min=%3d  max=%3d\n",
                    $st, $agg{$st}{n}, $avg, $agg{$st}{min} // 0, $agg{$st}{max} // 0;
            }
        }
    }
}

sub _current_artifact ($prospecting, $char_id) {
    for my $a (reverse @$prospecting) {
        return $a if $a->{char_id} eq $char_id && !$a->{collapse} && !$a->{breakthrough} && !$a->{stop};
    }
    return;
}

sub _current_market ($market, $char_id) {
    for my $m (reverse @$market) {
        return $m if $m->{char_id} eq $char_id;
    }
    return;
}

1;
