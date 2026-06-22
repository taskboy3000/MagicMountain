package MagicMountain::Command::end_season;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Model::Season;

has description => 'Finalize the active season, archive records, and clean up';
has usage       => "Usage: $0 end-season\n";

sub run ($self, @args) {
    my $result = eval { MagicMountain::Model::Season->finalize($self->app) };
    if ($@) {
        chomp $@;
        say "Error: $@";
        exit 1;
    }
    say "Season '$result->{label}' archived successfully.";
}

1;
