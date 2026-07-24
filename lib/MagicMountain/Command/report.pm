package MagicMountain::Command::report;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Model::Transcript;

has description => 'Aggregate transcript stats for tuning analysis.';
has usage => "Usage: $0 report [--transcript FILE] [--player ID|NAME] [--for-llm]\n"
           . "  --transcript FILE  Transcript path (default data/transcript.jsonl)\n"
           . "  --player ID|NAME   Filter to a specific character\n"
           . "  --for-llm          Output compact digest for LLM analysis\n";

sub run ($self, @args) {
    my ($transcript_path, $player_filter, $for_llm);
    for (my $i = 0; $i < @args; $i++) {
        if ($args[$i] eq '--transcript' && $i + 1 < @args) { $transcript_path = $args[++$i] }
        if ($args[$i] eq '--player' && $i + 1 < @args) { $player_filter = $args[++$i] }
        if ($args[$i] eq '--for-llm') { $for_llm = 1 }
    }

    my $transcript;
    if ($transcript_path) {
        $transcript = MagicMountain::Model::Transcript->new(file => $transcript_path);
    } else {
        $transcript = $self->app->transcript;
    }

    my @events = @{ $transcript->all_events };

    # Load character model and build bot/human lookup
    my %is_bot;
    eval { $self->app->characters->load };
    if ($self->app->characters->table) {
        for my $c (@{ $self->app->characters->find(sub { 1 }) }) {
            $is_bot{ $c->getCol('id') } = $c->getCol('is_bot') // 0;
        }
    }

    # Resolve player filter: try as ID first, then as name
    my $player_char_id = $player_filter;
    if ($player_filter && !exists $is_bot{$player_filter}) {
        for my $c (@{ $self->app->characters->find(sub { $_[0]->{name} eq $player_filter }) }) {
            $player_char_id = $c->getCol('id');
            last;
        }
    }

    # O(1) hash indexes into parallel arrays
    my @artifacts;
    my %art_idx_of;
    my @visits;
    my %visit_idx_of;
    my %sale_val;  # { bucket => { sale_type => { n, sum, min, max } } }

    for my $e (@events) {
        next if $player_char_id && $e->{char_id} ne $player_char_id;
        next if $e->{type} =~ /^policy_|^sim_|decay_tick|faction_snapshot/;

        my $char_id = $e->{char_id} // next;
        my $bot = $is_bot{$char_id} // 0;

        if ($e->{type} eq 'artifact_start') {
            $art_idx_of{$char_id} = $#artifacts + 1;
            push @artifacts, { char_id => $char_id, bot => $bot, pushes => 0, collapsed => 0, breakthrough => 0, stopped => 0, budget_exhausted => 0 };
        }
        elsif ($e->{type} eq 'push') {
            if (defined(my $idx = $art_idx_of{$char_id})) {
                $artifacts[$idx]{pushes}++;
            }
        }
        elsif ($e->{type} eq 'collapse') {
            if (defined(my $idx = $art_idx_of{$char_id})) {
                $artifacts[$idx]{collapsed} = 1;
                delete $art_idx_of{$char_id};
            }
        }
        elsif ($e->{type} eq 'breakthrough') {
            if (defined(my $idx = $art_idx_of{$char_id})) {
                $artifacts[$idx]{breakthrough} = 1;
                delete $art_idx_of{$char_id};
            }
        }
        elsif ($e->{type} eq 'stop') {
            if (defined(my $idx = $art_idx_of{$char_id})) {
                $artifacts[$idx]{stopped} = 1;
                delete $art_idx_of{$char_id};
            }
        }
        elsif ($e->{type} eq 'budget_exhausted') {
            if (defined(my $idx = $art_idx_of{$char_id})) {
                $artifacts[$idx]{budget_exhausted}++;
            }
        }
        elsif ($e->{type} eq 'market_visit') {
            delete $visit_idx_of{$char_id};
            $visit_idx_of{$char_id} = $#visits + 1;
            push @visits, { char_id => $char_id, bot => $bot, offers => 0, mismatches => 0, counters => 0, counters_accepted => 0, sales => 0, send_aways => 0, stand_pats => 0, stand_pat_successes => 0, sale_maxed => 0, over_budget => 0, influence_snubs => 0 };
        }
        elsif ($e->{type} eq 'offer') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{offers}++;
                $visits[$idx]{mismatches}++ unless $e->{match};
            }
        }
        elsif ($e->{type} eq 'counter_offer') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{counters}++;
            }
        }
        elsif ($e->{type} eq 'accept_counter') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{counters_accepted}++;
            }
        }
        elsif ($e->{type} eq 'sale') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{sales}++;
                my $v  = $e->{value} // 0;
                my $st = $e->{sale_type} // 'unknown';
                for my $bucket ($bot ? ('total', 'bot') : ('total', 'human')) {
                    $sale_val{$bucket}{$st}{n}++;
                    $sale_val{$bucket}{$st}{sum} += $v;
                    $sale_val{$bucket}{$st}{min} = $v if !defined($sale_val{$bucket}{$st}{min}) || $v < $sale_val{$bucket}{$st}{min};
                    $sale_val{$bucket}{$st}{max} = $v if !defined($sale_val{$bucket}{$st}{max}) || $v > $sale_val{$bucket}{$st}{max};
                }
            }
        }
        elsif ($e->{type} eq 'send_away') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{send_aways}++;
            }
        }
        elsif ($e->{type} eq 'stand_pat') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{stand_pats}++;
                $visits[$idx]{stand_pat_successes}++ if $e->{accepted};
            }
        }
        elsif ($e->{type} eq 'stand_pat_fail') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{stand_pats}++;
            }
        }
        elsif ($e->{type} eq 'sale_maxed') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{sale_maxed}++;
            }
        }
        elsif ($e->{type} eq 'over_budget') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{over_budget}++;
            }
        }
        elsif ($e->{type} eq 'influence_snub') {
            if (defined(my $idx = $visit_idx_of{$char_id})) {
                $visits[$idx]{influence_snubs}++;
            }
        }
    }

    # Deduplicate players in artifacts/visits
    my %seen_char;
    for (@artifacts, @visits) { $seen_char{ $_->{char_id} } = 1 }
    my @char_ids = sort keys %seen_char;

    # Aggregate prospecting counters
    my %p = (total => {}, bot => {}, human => {});
    for my $a (@artifacts) {
        my $b = $a->{bot} ? 'bot' : 'human';
        for my $bucket ('total', $b) {
            $p{$bucket}{expeditions}++;
            $p{$bucket}{pushes} += $a->{pushes};
            $p{$bucket}{collapsed}++ if $a->{collapsed};
            $p{$bucket}{breakthrough}++ if $a->{breakthrough};
            $p{$bucket}{stopped}++ if $a->{stopped};
            $p{$bucket}{budget_exhausted} += $a->{budget_exhausted};
        }
    }

    # Aggregate market counters
    my %m = (total => {}, bot => {}, human => {});
    for my $v (@visits) {
        my $b = $v->{bot} ? 'bot' : 'human';
        for my $bucket ('total', $b) {
            $m{$bucket}{visits}++;
            for my $k (qw(offers mismatches counters counters_accepted sales send_aways stand_pats stand_pat_successes sale_maxed over_budget influence_snubs)) {
                $m{$bucket}{$k} += $v->{$k};
            }
        }
    }

    # PVP analysis
    my %pvp;  # { total|bot|human => { effect_type => count } }
    my $pvp_cost_total = 0;
    eval { $self->app->pressures->load };
    if ($self->app->pressures->table) {
        my @pressures = values %{ $self->app->pressures->table };
        my %costs = (
            corner_market => $self->app->config->{pvp_cost_corner_market} // 50,
            spoil_lead    => $self->app->config->{pvp_cost_spoil_lead}    // 30,
            outbid        => $self->app->config->{pvp_cost_outbid}        // 75,
        );
        for my $p (@pressures) {
            my $bot = $is_bot{ $p->{attacker_id} } // 0 ? 'bot' : 'human';
            for my $bucket ('total', $bot) {
                $pvp{$bucket}{ $p->{effect_type} }++;
            }
            my $cp = $costs{ $p->{effect_type} } // 0;
            $pvp_cost_total += $cp;
        }
    }

    # Build output
    if ($for_llm) {
        $self->_llm_output(\%p, \%m, \%sale_val, \%pvp, $pvp_cost_total, \@char_ids, \%is_bot);
    } else {
        $self->_human_output(\%p, \%m, \%sale_val, \%pvp, $pvp_cost_total, \@char_ids);
    }
}

sub _llm_output ($self, $p, $m, $sv, $pvp, $pvp_cost, $char_ids, $is_bot) {
    my $n = scalar @$char_ids;
    my $n_bot   = scalar grep { $is_bot->{$_} } @$char_ids;
    my $n_human = $n - $n_bot;
    printf "characters: %d (human: %d, bot: %d)\n", $n, $n_human, $n_bot;

    my @section;

    # Prospecting section
    if ($p->{total}{expeditions}) {
        my @lines = ('=PROSPECTING=');
        for my $bucket ('total', 'bot', 'human') {
            next unless $p->{$bucket}{expeditions};
            my $exp = $p->{$bucket}{expeditions};
            my $push = $p->{$bucket}{pushes};
            my $col = $bucket eq 'total' ? 'all' : $bucket;
            push @lines, sprintf('  %-6s expeditions=%d pushes=%d avg_push=%.1f collapsed=%s breakthrough=%s stopped=%s budget_exhausted=%d',
                $col,
                $exp,
                $push,
                $push / $exp,
                _pct_str($p->{$bucket}{collapsed} || 0, $exp),
                _pct_str($p->{$bucket}{breakthrough} || 0, $exp),
                _pct_str($p->{$bucket}{stopped} || 0, $exp),
                $p->{$bucket}{budget_exhausted} || 0,
            );
        }
        push @section, join("\n", @lines);
    }

    # Market section
    if ($m->{total}{visits}) {
        my @lines = ('=MARKET=');
        for my $bucket ('total', 'bot', 'human') {
            next unless $m->{$bucket}{visits};
            my $vis = $m->{$bucket}{visits};
            my $off = $m->{$bucket}{offers} || 0;
            my $cnt = $m->{$bucket}{counters} || 0;
            my $sp  = $m->{$bucket}{stand_pats} || 0;
            my $col = $bucket eq 'total' ? 'all' : $bucket;
            push @lines, sprintf('  %-6s visits=%d offers=%d offers_per_visit=%.2f sales=%d mismatches=%d send_aways=%d counters_accepted=%s stand_pats_success=%s sale_maxed=%d over_budget=%d snubs=%d',
                $col,
                $vis, $off,
                $vis ? $off / $vis : 0,
                $m->{$bucket}{sales} || 0,
                $m->{$bucket}{mismatches} || 0,
                $m->{$bucket}{send_aways} || 0,
                _pct_str($m->{$bucket}{counters_accepted} || 0, $cnt),
                _pct_str($m->{$bucket}{stand_pat_successes} || 0, $sp),
                $m->{$bucket}{sale_maxed} || 0,
                $m->{$bucket}{over_budget} || 0,
                $m->{$bucket}{influence_snubs} || 0,
            );
        }
        push @section, join("\n", @lines);
    }

    # Sale prices section
    if (keys %{ $sv->{total} // {} }) {
        my @lines = ('=SALE PRICES=');
        my @stypes = sort keys %{ $sv->{total} };
        for my $st (@stypes) {
            my $info = sub {
                my $d = $sv->{total}{$st};
                my $avg = int($d->{sum} / $d->{n});
                return sprintf('n=%d avg=%d min=%d max=%d', $d->{n}, $avg, $d->{min}, $d->{max});
            };
            push @lines, sprintf('  %-15s %s', $st, $info->());
        }
        push @section, join("\n", @lines);
    }

    # PVP section
    if (keys %{ $pvp->{total} // {} }) {
        my @lines = ('=PVP=');
        push @lines, sprintf('  %-15s %6s %6s %10s', 'effect', 'total', 'bot', 'est_cost');
        for my $et (sort keys %{ $pvp->{total} }) {
            push @lines, sprintf('  %-15s %6d %6d %10d',
                $et,
                $pvp->{total}{$et} // 0,
                $pvp->{bot}{$et} // 0,
                ($pvp->{total}{$et} // 0) * ($self->app->config->{'pvp_cost_' . $et} // 50),
            );
        }
        push @lines, sprintf('  %-15s %6s %6s %10d', 'total', '', '', $pvp_cost);
        push @lines, '  (note: counts may undercount due to record cleanup during play)';
        push @section, join("\n", @lines);
    }

    print join("\n\n", @section) . "\n";
}

sub _pct_str ($n, $total) {
    return '0' unless $total;
    return sprintf('%d(%.1f%%)', $n, $n / $total * 100);
}

sub _human_output ($self, $p, $m, $sv, $pvp, $pvp_cost, $char_ids) {
    my $n = scalar @$char_ids;
    printf "Characters: %d\n", $n;

    if ($p->{total}{expeditions}) {
        printf "\n-- Prospecting ------------------------------\n";
        for my $bucket ('total', 'bot', 'human') {
            next unless $p->{$bucket}{expeditions};
            my $exp = $p->{$bucket}{expeditions};
            my $push = $p->{$bucket}{pushes};
            printf "  %s:\n", $bucket eq 'total' ? 'All' : ucfirst($bucket);
            printf "    Expeditions:      %d\n", $exp;
            printf "    Avg pushes/exp:   %.1f\n", $exp ? $push / $exp : 0;
            printf "    Collapse rate:    %.1f%%\n", $exp ? ($p->{$bucket}{collapsed} || 0) / $exp * 100 : 0;
            printf "    Breakthrough rate: %.1f%%\n", $exp ? ($p->{$bucket}{breakthrough} || 0) / $exp * 100 : 0;
            printf "    Stop rate:        %.1f%%\n", $exp ? ($p->{$bucket}{stopped} || 0) / $exp * 100 : 0;
            printf "    Budget exhausted: %d\n", $p->{$bucket}{budget_exhausted} || 0;
        }
    }

    if ($m->{total}{visits}) {
        printf "\n-- Market -----------------------------------\n";
        for my $bucket ('total', 'bot', 'human') {
            next unless $m->{$bucket}{visits};
            my $vis = $m->{$bucket}{visits};
            my $off = $m->{$bucket}{offers} || 0;
            my $cnt = $m->{$bucket}{counters} || 0;
            my $sp  = $m->{$bucket}{stand_pats} || 0;
            printf "  %s:\n", $bucket eq 'total' ? 'All' : ucfirst($bucket);
            printf "    Visits:           %d\n", $vis;
            printf "    Avg offers/visit: %.1f\n", $vis ? $off / $vis : 0;
            printf "    Counter-offers:   %d (%.1f%% accepted)\n", $cnt, $cnt ? ($m->{$bucket}{counters_accepted} || 0) / $cnt * 100 : 0;
            printf "    Send-aways:       %d\n", $m->{$bucket}{send_aways} || 0;
            printf "    Stand-pats:       %d (%.1f%% success)\n", $sp, $sp ? ($m->{$bucket}{stand_pat_successes} || 0) / $sp * 100 : 0;
            printf "    Sales:            %d\n", $m->{$bucket}{sales} || 0;
            printf "    Mismatches:       %d\n", $m->{$bucket}{mismatches} || 0;
            printf "    Sale maxed:       %d\n", $m->{$bucket}{sale_maxed} || 0;
            printf "    Over budget:      %d\n", $m->{$bucket}{over_budget} || 0;
            printf "    Influence snubs:  %d\n", $m->{$bucket}{influence_snubs} || 0;
        }

        # Aggregate sale prices
        if (keys %{ $sv->{total} // {} }) {
            printf "\n  Sale prices by type:\n";
            for my $st (sort keys %{ $sv->{total} }) {
                for my $bucket ('total', 'bot', 'human') {
                    next unless $sv->{$bucket}{$st};
                    my $d  = $sv->{$bucket}{$st};
                    my $avg = int($d->{sum} / $d->{n});
                    printf "    %-15s %-6s n=%3d  avg=%3d  min=%3d  max=%3d\n",
                        $st, "($bucket)", $d->{n}, $avg, $d->{min} // 0, $d->{max} // 0;
                }
            }
        }
    }

    if (keys %{ $pvp->{total} // {} }) {
        printf "\n-- PVP --------------------------------------\n";
        printf "  Effect         Total  Bot  Est Cost\n";
        for my $et (sort keys %{ $pvp->{total} }) {
            printf "  %-15s %5d %4d %8d\n",
                $et,
                $pvp->{total}{$et} // 0,
                $pvp->{bot}{$et} // 0,
                ($pvp->{total}{$et} // 0) * ($self->app->config->{'pvp_cost_' . $et} // 50);
        }
        printf "  %-15s %5s %4s %8d\n", 'total', '', '', $pvp_cost;
        printf "  (note: counts may undercount due to record cleanup during play)\n";
    }
}

1;

__END__

=pod

=head1 NAME

report - Aggregate transcript stats for tuning analysis

=head1 SYNOPSIS

  script/mountain report
  script/mountain report --for-llm
  script/mountain report --player Alice
  script/mountain report --player bot-001 --for-llm
  script/mountain report --transcript /path/to/transcript.jsonl

=head1 DESCRIPTION

Reads the game transcript (JSONL event log) and produces aggregate statistics
about player and bot activity, including prospecting outcomes, market behavior,
sale prices, and PVP pressure actions.

Results are split into B<total>, B<bot>, and B<human> buckets wherever
characters have the C<is_bot> flag set.

=head1 OPTIONS

=over

=item B<--transcript FILE>

Path to the transcript JSONL file. Defaults to C<data/transcript.jsonl>.

=item B<--player ID|NAME>

Filter results to a single character, specified by UUID or display name.
Useful for drilling into a specific player or bot's activity.

=item B<--for-llm>

Output a compact key=value digest suitable for LLM analysis prompts. Each
section (PROSPECTING, MARKET, SALE PRICES, PVP) is labeled with C<=SECTION=>
headers. The character count line serves as a summary header.

=back

=head1 SECTIONS

=head2 Prospecting

Tracks artifact_start, push, collapse, breakthrough, stop, and
budget_exhausted events. Reports expedition count, average pushes per
expedition, and outcome rates (collapse, breakthrough, stop percentages).

=head2 Market

Tracks market_visit, offer, sale, send_away, stand_pat, stand_pat_fail,
counter_offer, accept_counter, sale_maxed, over_budget, and influence_snub
events. Reports visit count, offers per visit, sales, mismatches, and
negotiation outcomes.

=head2 Sale Prices

Breaks down sale values by C<sale_type> (direct, corner, loyalty, etc.)
with count, average, minimum, and maximum values. Split by bot/human.

=head2 PVP

Reads the C<Pressure> model to report PVP actions by C<effect_type>
(corner_market, spoil_lead, outbid). Shows counts per type, bot-attacker
breakdown, and estimated scrap costs computed from current config values.

B<Warning:> Pressure records are cleaned up during gameplay when fully
consumed or past the max age. PVP counts reflect B<currently stored>
records only and may undercount.

=head1 OUTPUT FORMATS

=head2 Default (human-readable)

Tabular format with labeled sections. Example:

  Characters: 5

  -- Prospecting ------------------------------
    All:
      Expeditions:      14
      Avg pushes/exp:   3.1
      ...

=head2 --for-llm (compact)

Key=value lines per bucket. Example:

  characters: 5 (human: 2, bot: 3)
  =PROSPECTING=
    all    expeditions=14 pushes=44 avg_push=3.1 collapsed=2(14.3%) ...

=head1 DATA SOURCES

=over

=item B<Transcript> (C<data/transcript.jsonl>)

The primary event log. Written by C<Activity::Prospecting>,
C<Activity::MarketVisit>, and C<Activity::Pawn> during gameplay.

=item B<Character model> (C<data/characters.json>)

Loaded to determine C<is_bot> status for each character referenced in the
transcript.

=item B<Pressure model> (C<data/pressures.json>)

Loaded for PVP analysis. Contains per-attempt records with effect_type,
attacker_id, target_id, and consumption flags.

=back

=head1 LIMITATIONS

=over

=item PVP costs are estimated from current config (C<pvp_cost_corner_market>,
C<pvp_cost_spoil_lead>, C<pvp_cost_outbid>). Actual per-action costs are
not persisted on Pressure records.

=item Pressure records may be purged during gameplay (see L</PVP> section).
The report reads only surviving rows.

=item The report is a snapshot analysis tool, not a live monitoring system.

=back

=cut
