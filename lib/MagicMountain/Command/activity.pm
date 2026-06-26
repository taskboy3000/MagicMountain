package MagicMountain::Command::activity;
use Mojo::Base 'Mojolicious::Command', '-signatures';
use open ':std', ':encoding(UTF-8)';

has description => 'Show a human-readable digest of recent player activity from the transcript log';
has usage       => "Usage: $0 activity [--lines N] [--player NAME] [--since TS]\n";

sub run ($self, @args) {
    my ($lines, $player, $since);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--lines' && @args) {
            $lines = 0 + shift @args;
        } elsif ($arg eq '--player' && @args) {
            $player = shift @args;
        } elsif ($arg eq '--since' && @args) {
            $since = 0 + shift @args;
        }
    }
    $lines //= 30;

    my @events = @{ $self->app->transcript->all_events };
    @events = grep { ($_->{narrative} // '') =~ /\Q$player/i } @events if $player;
    @events = grep { ($_->{ts} // 0) >= $since } @events if $since;

    my $start = @events > $lines ? $#events - $lines + 1 : 0;
    for my $i ($start .. $#events) {
        my $e = $events[$i];
        my $ts   = $e->{ts} ? _time($e->{ts}) : '--:--:--';
        my $type = $e->{type} // '?';
        my $narr = $e->{narrative} // '';

        my $extra = '';
        if ($e->{value} && $e->{value} ne '0') {
            if ($type eq 'sale') {
                $extra = sprintf(" (+%d scrap)", $e->{value});
            } elsif ($type eq 'breakthrough') {
                $extra = sprintf(" (value %d)", $e->{value});
            }
        }
        if ($type eq 'push') {
            $extra = sprintf(" (stage %s, ratio %.2f)", $e->{stage} // '?', $e->{ratio} // 0);
        }
        if ($type eq 'counter_offer') {
            $extra = sprintf(" (%d scrap)", $e->{offered_value} // $e->{value} // 0);
        }
        if ($type eq 'sale') {
            $extra = sprintf(" (type=%s, %d scrap)", $e->{sale_type} // '?', $e->{value} // 0);
        }

        printf "%s  %-16s %s%s\n", $ts, $type, $narr, $extra;
    }
}

sub _time ($ts) {
    my @t = localtime $ts;
    sprintf "%02d:%02d:%02d", $t[2], $t[1], $t[0];
}

1;
