package MagicMountain::Command::init;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use File::Slurp qw(write_file);

has description => 'Reset all game data and create a fresh season. Wipes accounts, characters, seasons, and all state.';
has usage       => "Usage: $0 init [--label 'Season 1'] [--length 30] [--end-of-day-hour 0] [--force]\n";

sub run ($self, @args) {
    my ($label, $length, $end_of_day_hour, $force);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--label' && @args) {
            $label = shift @args;
        } elsif ($arg eq '--length' && @args) {
            $length = shift @args;
        } elsif ($arg eq '--end-of-day-hour' && @args) {
            $end_of_day_hour = shift @args;
        } elsif ($arg eq '--force') {
            $force = 1;
        }
    }

    my $app   = $self->app;
    my $dir   = $app->dataDir;

    unless ($force) {
        say "This will DELETE all accounts, characters, seasons, and game data in $dir.";
        say "Are you sure? Type 'yes' to continue:";
        my $answer = <STDIN>;
        chomp $answer;
        unless ($answer eq 'yes') {
            say "Aborted.";
            exit 1;
        }
    }

    # Wipe all data files
    my @json_files = qw(
        accounts.json characters.json sessions.json seasons.json
        shed.json activities.json dispositions.json
        faction_snapshots.json season_records.json
    );
    for my $f (@json_files) {
        my $path = "$dir/$f";
        if (-e $path) {
            write_file($path, '{}');
            say "  wiped $f";
        } else {
            write_file($path, '{}');
            say "  created $f";
        }
    }

    my @jsonl_files = qw(audit.jsonl transcript.jsonl);
    for my $f (@jsonl_files) {
        my $path = "$dir/$f";
        if (-e $path) {
            write_file($path, '');
            say "  wiped $f";
        } else {
            write_file($path, '');
            say "  created $f";
        }
    }

    # Bust lazy model caches so they reload from empty files
    delete $app->{$_} for qw(accounts characters seasons shed session_store transcript prospecting market audit_log disposition faction_snapshots season_records);

    # Create fresh season
    $length         //= $app->config->{default_season_length} // 30;
    $end_of_day_hour //= $app->config->{end_of_day_hour} // 0;

    if (!$label) {
        my $prefix = $app->config->{default_season_label_prefix} // 'Season';
        $label = "$prefix 1";
    }

    my $season = $app->seasons->create(
        label           => $label,
        length          => $length,
        day             => 1,
        end_of_day_hour => $end_of_day_hour,
        status          => 'active',
    );
    $season->save;

    say "Season created:";
    say "  id:              " . $season->getCol('id');
    say "  label:           " . $season->getCol('label');
    say "  length (days):   " . $season->getCol('length');
    say "  day:             " . $season->getCol('day');
    say "  end_of_day_hour: " . $season->getCol('end_of_day_hour');
    say "  status:          " . $season->getCol('status');
    say "Done. All game data has been reset.";
}

1;
