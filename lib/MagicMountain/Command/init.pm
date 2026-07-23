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
use File::Path qw(remove_tree);
use YAML::XS;

has description => 'Reset all game data and create a fresh season. Wipes accounts, characters, seasons, and all state. Optionally regenerates config.';
has usage       => "Usage: $0 init [--label 'Season 1'] [--length 30] [--end-of-day-hour 0] [--force] [--with-config]\n";

sub _random_hex ($self, $bytes) {
    open my $fh, '<:raw', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
    my $buf;
    read $fh, $buf, $bytes;
    close $fh;
    return unpack('H*', $buf);
}

sub _write_default_config ($self, $path, $app) {
    my $cfg = $app->defaultConfig;
    my $defaults = {
        secrets        => [$self->_random_hex(32)],
        admin_secret   => $self->_random_hex(32),
        end_of_day_hour    => $cfg->{end_of_day_hour} // 0,
        admin_email        => 'root@localhost',
        bcrypt_cost        => 10,
        bots => {
            count    => 5,
            profiles => [
                { id => 'stage_guard_opportunist' },
                { id => 'greed_desperate' },
                { id => 'value_hoarder' },
                { id => 'fixed_highest' },
                { id => 'instability_loyalist' },
            ],
        },
    };
    YAML::XS::DumpFile($path, $defaults);
    say "  wrote $path";
}

sub run ($self, @args) {
    my ($label, $length, $end_of_day_hour, $force, $with_config);
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
        } elsif ($arg eq '--with-config') {
            $with_config = 1;
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

    # Wipe entire data directory
    if (-e $dir) {
        remove_tree($dir, { safe => 0 });
        say "  wiped data directory";
    }
    mkdir $dir or die "Cannot create data directory $dir: $!";
    say "  created data directory";

    # Regenerate config if requested
    if ($with_config) {
        my $cfg_path = $app->configFile;
        $self->_write_default_config($cfg_path, $app);
        my $local_path = $app->home . '/magic_mountain.local.yml';
        unlink $local_path if -e $local_path;
        say "  removed $local_path (will be auto-generated on next start)";
    }

    # Bust lazy model caches so they reload
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
