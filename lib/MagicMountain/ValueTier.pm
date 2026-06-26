package MagicMountain::ValueTier;
use Mojo::Base '-base', '-signatures';

my @TIERS = (
    { max => 5,   label => 'negligible' },
    { max => 10,  label => 'low' },
    { max => 20,  label => 'middling' },
    { max => 35,  label => 'ordinary' },
    { max => 55,  label => 'uncommon' },
    { max => 80,  label => 'rare' },
    { max => 999, label => 'high' },
);

sub describe ($value) {
    $value //= 0;
    for my $tier (@TIERS) {
        return $tier->{label} if $value <= $tier->{max};
    }
    return 'high';
}

1;
