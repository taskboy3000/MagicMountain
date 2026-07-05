package TestEnv;
use strict;
use warnings;
use File::Temp qw(tempdir);

# Ensure test mode is active before any app code loads.
# Using = (not ||=) so that building the app in any mode other
# than 'test' is impossible from within the test suite.
BEGIN { $ENV{MOJO_MODE} = 'test' }

# Fixed seed for reproducible random sequences across test runs.
# Individual tests may override this locally with local $ENV{MM_RAND_SEED}.
BEGIN { $ENV{MM_RAND_SEED} //= '42' }

sub import {
    my $class = shift;
    my %args  = @_;

    if (!$ENV{MM_DATA_DIR}) {
        $ENV{MM_DATA_DIR} = tempdir(CLEANUP => 1);
    }
}

1;
