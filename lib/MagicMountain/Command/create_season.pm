package MagicMountain::Command::create_season;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Create a new game season';
has usage       => "Usage: $0 create-season [--label 'Season 1'] [--length 30] [--end-of-day-hour 0]\n";

sub run ($self, @args) {
    my ($label, $length, $end_of_day_hour);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--label' && @args) {
            $label = shift @args;
        } elsif ($arg eq '--length' && @args) {
            $length = shift @args;
        } elsif ($arg eq '--end-of-day-hour' && @args) {
            $end_of_day_hour = shift @args;
        }
    }

    $label          //= 'Season 1';
    $length         //= 30;
    $end_of_day_hour //= $self->app->config->{end_of_day_hour} // 0;

    my $season = $self->app->seasons->create(
        label           => $label,
        length          => $length,
        day             => 1,
        end_of_day_hour => $end_of_day_hour,
    );
    $season->save;

    say "Season created:";
    say "  id:              " . $season->getCol('id');
    say "  label:           " . $season->getCol('label');
    say "  length (days):   " . $season->getCol('length');
    say "  day:             " . $season->getCol('day');
    say "  end_of_day_hour: " . $season->getCol('end_of_day_hour');
}

1;
