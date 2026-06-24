use strict;
use warnings;
use Test::More;

my $js = 'public/js/game.js';
ok -f $js, "$js exists";

my $output = `node --check '$js' 2>&1`;
my $exit   = $? >> 8;

is $exit, 0, "node --check $js exits 0"
    or diag $output;

done_testing;
