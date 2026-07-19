use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::Mojo;
use Test::More;

BEGIN { $ENV{MOJO_MODE} = 'test' }

my $t = Test::Mojo->new('MagicMountain');
$t->app->log->level('fatal');

# Unauthenticated access redirects to login
$t->get_ok('/pawn')->status_is(302);

done_testing;
