package TestInit;
use Modern::Perl;

# Ensure test mode is active for all tests
BEGIN { $ENV{MOJO_MODE} ||= 'test' }

1;
