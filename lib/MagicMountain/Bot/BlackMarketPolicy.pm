package MagicMountain::Bot::BlackMarketPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    default   => sub ($char, $item, $premium_mult, $p) { 0 },
    greedy    => sub ($char, $item, $premium_mult, $p) { $premium_mult >= ($p->{threshold} // 1.5) },
    desperate => sub ($char, $item, $premium_mult, $p) { $premium_mult >= ($p->{threshold} // 1.2) },
);

sub should_use ($char, $item, $premium_mult, $policy) {
    my $name = $policy->{name} // 'default';
    my $handler = $POLICIES{$name} or return 0;
    return $handler->($char, $item, $premium_mult, $policy->{params} // {});
}

1;
