use Modern::Perl;
use Test::More;
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::ValueTier;

my @cases = (
    [ 0,   'negligible' ],
    [ 1,   'negligible' ],
    [ 5,   'negligible' ],
    [ 6,   'low'        ],
    [ 10,  'low'        ],
    [ 11,  'middling'   ],
    [ 20,  'middling'   ],
    [ 21,  'ordinary'   ],
    [ 35,  'ordinary'   ],
    [ 36,  'uncommon'   ],
    [ 55,  'uncommon'   ],
    [ 56,  'rare'       ],
    [ 80,  'rare'       ],
    [ 81,  'high'       ],
    [ 200, 'high'       ],
    [ undef, 'negligible' ],
);

for my $c (@cases) {
    my ($value, $expected) = @$c;
    is MagicMountain::ValueTier::describe($value), $expected,
        "describe($value) => $expected";
}

done_testing;
