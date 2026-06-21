package MagicMountain::Command::simulate;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use Getopt::Long qw(GetOptionsFromArray);
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use File::Copy qw(copy);
use MagicMountain::Model::Transcript;

has description => 'Run a bot simulation season.';
has usage => "usage: $0 simulate [OPTIONS]\n"
           . "  --count N     Number of bots (default 5)\n"
           . "  --days N      Season length in days (default 30)\n"
           . "  --seed N      RNG seed\n"
           . "  --output FILE Transcript output path\n";

sub run ($self, @args) {
    my $count   = 5;
    my $days    = 30;
    my $seed    = undef;
    my $output  = undef;

    GetOptionsFromArray(\@args,
        'count=i'  => \$count,
        'days=i'   => \$days,
        'seed=i'   => \$seed,
        'output=s' => \$output,
    );

    srand($seed) if defined $seed;

    my $app = $self->app;
    my $data_dir = tempdir(CLEANUP => 1);
    local $ENV{MM_DATA_DIR} = $data_dir;
    delete $app->{dataDir};  # Reset cached attribute so $app->dataDir re-evaluates
    local $ENV{MM_SKIP_SEASON_CHECK} = 1;

    # Initialize empty data files
    write_file("$data_dir/accounts.json",   '{}');
    write_file("$data_dir/characters.json", '{}');
    write_file("$data_dir/sessions.json",   '{}');
    write_file("$data_dir/activities.json", '{}');
    write_file("$data_dir/shed.json",       '{}');
    write_file("$data_dir/seasons.json",    '{}');

    # Pre-load models so they read from the new files
    my $accts  = $app->accounts;
    my $chars  = $app->characters;
    my $season = $app->seasons;
    my $shed   = $app->shed;

    # Create an active season
    my $s = $season->create(
        label   => 'Simulation 1',
        length  => $days,
        day     => 1,
        status  => 'active',
    );
    $s->save;
    $app->log->info(sprintf("Created season %s (%d days)", $s->getCol('id'), $days));

    # Create bot accounts and characters
    my @bot_names;
    my @bot_chars;
    for my $i (1 .. $count) {
        my $name = sprintf("bot-%03d", $i);
        push @bot_names, $name;

        my $a = $accts->create(username => $name);
        $a->save;

        my $c = $chars->create(
            name              => $name,
            account_id        => $a->getCol('id'),
            season_id         => $s->getCol('id'),
            score             => 0,
            scrap             => 0,
            action_points     => 15,
            action_points_max => 15,
        );
        $c->save;
        push @bot_chars, $c;
    }

    $app->log->info(sprintf("Created %d bots", scalar @bot_chars));

    # Open transcript (direct instance injected into app to override lazy loader)
    my $transcript_file = "$data_dir/transcript.jsonl";
    $app->{transcript} = MagicMountain::Model::Transcript->new(file => $transcript_file);
    my $transcript = $app->transcript;
    $transcript->log_event({
        type      => 'sim_start',
        run_id    => $s->getCol('id'),
        bot_count => $count,
        day       => $days,
        narrative => sprintf("Simulation %s: %d bots, %d days.", $s->getCol('id'), $count, $days),
    });

    # Run the simulation day loop
    my $maint = $app->maintenance;
    for my $day (1 .. $days) {
        for my $char (@bot_chars) {
            $self->_run_bot_day($app, $char);
        }
        # Advance day and refresh AP for next day
        $maint->on_maintenance->($maint) if $day < $days;
    }

    $transcript->log_event({
        type      => 'sim_end',
        run_id    => $s->getCol('id'),
        narrative => sprintf("Simulation %s complete.", $s->getCol('id')),
    });

    # Copy or print transcript path
    if ($output) {
        copy($transcript_file, $output);
        $app->log->info(sprintf("Transcript written to %s", $output));
    } else {
        print "Transcript: $transcript_file\n";
    }
}

sub _run_bot_day ($self, $app, $char) {
    my $prospecting = $app->prospecting;
    my $market      = $app->market;
    my $shed        = $app->shed;

    # Prospecting phase
    while (($char->getCol('action_points') // 0) >= 2) {
        my $activity = $prospecting->create(char_id => $char->getCol('id'));
        my $result = $activity->dispatch($char, 'begin');
        last unless $result->{view}{ok};

        # Push until the naive policy says stop
        my $should_stop = 0;
        while (!$should_stop) {
            my $r = $activity->dispatch($char, 'push');
            my $view = $r->{view};
            last unless $view->{ok};

            if ($view->{result} eq 'collapse' || $view->{result} eq 'breakthrough') {
                last;
            }
            if ($view->{result} eq 'push') {
                my $stage = $view->{artifact}{stage} // '';
                if ($stage eq 'unstable') {
                    $activity->dispatch($char, 'stop');
                    $should_stop = 1;
                    last;
                }
            }
        }
    }

    # Market phase
    while (($char->getCol('action_points') // 0) >= 1) {
        my $shed_items = $shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
        last unless @$shed_items;

        my $activity = $market->create(char_id => $char->getCol('id'));
        my $result = $activity->dispatch($char, 'begin');
        last unless $result->{view}{ok};

        # Offer the first (oldest) shed item
        my $item = $shed_items->[0];
        $activity->dispatch($char, 'offer', shed_item_id => $item->getCol('id'));
        # offer handler concludes the visit (sale or no_sale), activity is deleted
    }
}

1;

__END__

=head1 SYNOPSIS

  perl -Ilib script/mountain simulate --count 8 --days 30 --seed 42
  perl -Ilib script/mountain simulate --count 5 --days 60 --seed 1 --output results.jsonl

=head1 DESCRIPTION

Runs a bot simulation season against the real game engine. Bots exercise the
full game loop (prospect -> shed -> market -> sell) using the same dispatch(),
transition tables, persistence, and invariants as human players - just without
the HTTP layer.

Each simulation creates a fresh set of data files in a temp directory, runs
the specified number of bots through the specified number of in-game days, and
writes a JSONL transcript of every event to an output file.

=head1 OPTIONS

=over

=item B<--count> I<N>

Number of bot players. Defaults to 5. Each bot gets a unique name (bot-001,
bot-002, etc.), its own account, and its own seasonal character with 15 AP/day.

=item B<--days> I<N>

Season length in days. Defaults to 30. Day rollover (AP refresh, artifact
decay, season day increment) uses the same C<on_maintenance> callback as
production.

=item B<--seed> I<N>

RNG seed for reproducible runs. Same seed + same count + same days produces
identical results. Useful for comparing balance changes.

=item B<--output> I<FILE>

Transcript output path. If omitted, prints the temp file path to stdout.
Transcripts are JSONL - one JSON object per line, each with C<ts>, C<type>,
and C<narrative> fields.

=head1 BOT STRATEGY

The current bot uses a single hardcoded naive strategy:

=over

=item B<Prospecting>: Push until the artifact reaches C<unstable> stage,
then stop. On collapse or breakthrough, move on.

=item B<Selling>: On a market visit, offer the oldest shed item. If the
customer wants it, sell. Otherwise, the customer leaves. Visit ends.

=item B<Skills>: All skills are zero (baseline).

=back

See L<GAME_ARCHITECTURE.md|/Future Expansion> for plans to add pluggable
push/sell policies.

=head1 OUTPUT

Transcript events include (but are not limited to):

  artifact_start  - A bot drew an artifact from the mountain
  push            - A destabilization attempt
  collapse        - Total loss
  breakthrough    - Evolution cashout
  stop            - Safe recovery into shed
  shed_entry      - Artifact placed in inventory
  market_visit    - Bot entered the Bazaar
  offer           - Customer made an offer (match or mismatch)
  sale            - Successful sale
  sim_start       - Simulation metadata
  sim_end         - Simulation complete

Each event includes a C<narrative> field with a human-readable description.
The structured fields (C<value>, C<instability>, C<stage>, etc.) are available
for programmatic analysis.

=head1 ANALYSIS

  perl script/analyze results.jsonl

Prints: artifacts per bot, push distribution, collapse/breakthrough/stop rates,
average sale values, and score ranges.

=head1 SEE ALSO

L<MagicMountain::Model::Transcript>, L<script/analyze>
