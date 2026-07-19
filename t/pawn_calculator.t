use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::More;

use_ok 'MagicMountain::Service::PawnCalculator';

my $calc = MagicMountain::Service::PawnCalculator->new(app => undef);

# premium_multiplier returns one of four discrete values
my %seen;
for (1 .. 100) {
    my $v = $calc->premium_multiplier;
    ok($v == 2.0 || $v == 2.5 || $v == 3.0 || $v == 3.5, "premium_multiplier returns valid value ($v)")
        or diag "got $v";
    $seen{$v}++;
}
ok(scalar keys %seen >= 2, 'premium_multiplier hits at least 2 different values in 100 rolls');

# seizure_chance formula
is($calc->seizure_chance(0),   0.05, 'seizure_chance at value=0');
is($calc->seizure_chance(100), 0.20, 'seizure_chance at value=100');
is($calc->seizure_chance(200), 0.35, 'seizure_chance at value=200');
is($calc->seizure_chance(999), 0.35, 'seizure_chance caps at 0.35');

done_testing;
