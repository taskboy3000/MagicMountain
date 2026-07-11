package MagicMountain::Command::end_season;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Service::SeasonFinalizer;

has description => 'Finalize the active season, archive records, and clean up';
has usage       => "Usage: $0 end-season\n";

sub run ($self, @args) {
    my $result = eval { MagicMountain::Service::SeasonFinalizer->new(app => $self->app)->finalize };
    if ($@) {
        chomp $@;
        say "Error: $@";
        exit 1;
    }
    say "Season '$result->{label}' archived successfully.";
}

1;
