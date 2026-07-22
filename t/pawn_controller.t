use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::Mojo;
use Test::More;
use TestEnv;

my $t = TestEnv->create_app;
$t->app->log->level('fatal');

# Unauthenticated access redirects to login
$t->get_ok('/pawn')->status_is(302);

done_testing;
