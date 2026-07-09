package MagicMountain::Command::advance_day;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Trigger daily maintenance (advance season day, refresh AP, apply decay)';
has usage       => "Usage: $0 advance-day\n";

sub run ($self, @args) {
    my $app = $self->app;
    my $maint = $app->maintenance;

    my $season_before = $app->active_season;
    my $day_before = $season_before ? $season_before->getCol('day') : undef;

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
