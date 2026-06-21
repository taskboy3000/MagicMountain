package MagicMountain::Command::advance_day;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Trigger daily maintenance (advance season day, refresh AP, apply decay)';
has usage       => "Usage: $0 advance-day\n";

sub run ($self, @args) {
    my $app = $self->app;
    my $maint = $app->maintenance;

    $maint->on_maintenance->($maint);

    my $season = $app->active_season;
    if ($season) {
        printf "Day advanced to %d\n", $season->getCol('day') // '?';
    } else {
        say "No active season found.";
    }
}

1;
