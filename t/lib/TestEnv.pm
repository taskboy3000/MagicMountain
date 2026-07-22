package TestEnv;
use strict;
use warnings;
use File::Temp qw(tempdir);
use Test::Mojo;

# Ensure test mode is active before any app code loads.
# Using = (not ||=) so that building the app in any mode other
# than 'test' from within the test suite is impossible.
BEGIN { $ENV{MOJO_MODE} = 'test' }

# Web integration tests (Test::Mojo) are gated behind $ENV{GITHUB_ACTIONS}
# to avoid flaky Mojo::Reactor::EV race conditions on CI. Add
#   if ($ENV{GITHUB_ACTIONS}) { plan skip_all => 'reason'; }
# to any new web test file that may fail nondeterministically in GitHub Actions.

# Fixed seed for reproducible random sequences across test runs.
# Individual tests may override this locally with local $ENV{MM_RAND_SEED}.
BEGIN { $ENV{MM_RAND_SEED} //= '42' }

sub create_app {
    my $t = Test::Mojo->new('MagicMountain');
    $t->ua->on(start => sub {
        my ($ua, $tx) = @_;
        my $ct = $tx->req->headers->content_type // '';
        $tx->req->headers->accept('application/json') if $ct eq 'application/json';
    });
    return $t;
}

sub import {
    my $class = shift;
    my %args  = @_;

    if (!$ENV{MM_DATA_DIR}) {
        $ENV{MM_DATA_DIR} = tempdir(CLEANUP => 1);
    }
}

1;
