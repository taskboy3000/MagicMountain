package MagicMountain::Command::advance_day;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use IPC::Open3;
use Symbol 'gensym';

has description => 'Trigger daily maintenance (advance season day, refresh AP, apply decay)';
has usage       => "Usage: $0 advance-day\n";

sub run ($self, @args) {
    my $app = $self->app;
    my $maint = $app->maintenance;

    my $season_before = $app->active_season;
    my $day_before = $season_before ? $season_before->getCol('day') : undef;

    my $daemon_url = $ENV{MOUNTAIN_DAEMON_URL}
        // $app->config->{port}
        // 9000;
    $daemon_url = "http://localhost:$daemon_url" if $daemon_url =~ /^\d+$/;
    $daemon_url =~ s|/$||;

    my @cmd = ($^X, '-Ilib', 'script/mountain', 'bot-turn');
    local %ENV = %ENV;
    $ENV{MM_SKIP_CATCHUP} = '1';
    $ENV{MOUNTAIN_DAEMON_URL} = $daemon_url;

    my $pid = open3(my $in, my $out, my $err = gensym(), @cmd);
    close $in;

    my $exit_code = $?;
    my @bot_output = <$out>;
    close $out;
    close $err;

    if ($exit_code != 0) {
        $app->log->warn(sprintf(
            "Bot turn subprocess exited with code %d; rolling over anyway",
            $exit_code >> 8
        ));
    }

    $maint->on_maintenance->($maint);

    my $season_after = $app->active_season;
    if ($season_after) {
        my $day = $season_after->getCol('day') // '?';
        my $len = $season_after->getCol('length') // '?';
        printf "Day advanced to %d (season length %d)\n", $day, $len;
    } elsif ($day_before) {
        printf "Season ended at day %d (exceeded configured length). New season may be created on next game load.\n", $day_before + 1;
    } else {
        say "No active season found.";
    }
}

1;
