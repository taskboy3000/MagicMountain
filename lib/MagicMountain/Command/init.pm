package MagicMountain::Command::init;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Session;
use MagicMountain::Model::Season;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::ArtifactDisposition;
use MagicMountain::Model::FactionSnapshot;
use MagicMountain::Model::SeasonRecord;

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

    if (!$force) {
        say "This will DELETE all accounts, characters, seasons, and game data in $dir.";
        say "Are you sure? Type 'yes' to continue:";
        my $answer = <STDIN>;
        chomp $answer;
        if ($answer ne 'yes') {
            say "Aborted.";
            exit 1;
        }
    }

    # Wipe all data files through Model API
    my @models = (
        ['accounts.json',        'MagicMountain::Model::Account'],
        ['characters.json',      'MagicMountain::Model::Character'],
        ['sessions.json',        'MagicMountain::Model::Session'],
        ['seasons.json',         'MagicMountain::Model::Season'],
        ['shed.json',            'MagicMountain::Model::ShedItem'],
        ['activities.json',      'MagicMountain::Model'],
        ['dispositions.json',    'MagicMountain::Model::ArtifactDisposition'],
        ['faction_snapshots.json','MagicMountain::Model::FactionSnapshot'],
        ['season_records.json',  'MagicMountain::Model::SeasonRecord'],
    );
    for my $entry (@models) {
        my ($filename, $class) = @$entry;
        my $path = "$dir/$filename";
        $class->new(file => $path)->save;
        say -e $path ? "  wiped $filename" : "  created $filename";
    }

    for my $f (qw(audit.jsonl transcript.jsonl)) {
        my $path = "$dir/$f";
        my $existed = -e $path;
        unlink $path;
        say $existed ? "  wiped $f" : "  created $f";
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
