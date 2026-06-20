package MagicMountain::Command::create_season;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Create a new game season';
has usage       => "Usage: $0 create-season [--label 'Season 1'] [--length 30] [--end-of-day-hour 0] [--force]\n";

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

    $self->app->seasons->load;
    my $active = $self->app->seasons->find(sub { $_->{status} eq 'active' });
    if (@$active && !$force) {
        say "An active season already exists (" . $active->[0]->getCol('label') . ").";
        say "Use --force to archive it and create a new season.";
        exit 1;
    }

    if (@$active && $force) {
        my $old = $active->[0];
        $old->setCol('status', 'archived');
        $old->save;
        say "Previous season '" . $old->getCol('label') . "' archived.";
    }

    $length         //= $self->app->config->{default_season_length} // 30;
    $end_of_day_hour //= $self->app->config->{end_of_day_hour} // 0;

    if (!$label) {
        my $prefix = $self->app->config->{default_season_label_prefix} // 'Season';
        my $max_num = 0;
        my $all = $self->app->seasons->all;
        my $re = qr/^\Q$prefix\E\s+(\d+)$/;
        for my $id (keys %$all) {
            my $row = $all->{$id};
            if ($row->{label} =~ $re) {
                my $n = $1;
                $max_num = $n if $n > $max_num;
            }
        }
        $label = "$prefix " . ($max_num + 1);
    }

    my $season = $self->app->seasons->create(
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
}

1;
