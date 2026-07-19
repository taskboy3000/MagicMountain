package MagicMountain::Bot::BlackMarketPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    default   => sub ($premium_mult, $p) { 0 },
    greedy    => sub ($premium_mult, $p) { $premium_mult >= ($p->{threshold} // 1.5) },
    desperate => sub ($premium_mult, $p) { $premium_mult >= ($p->{threshold} // 1.2) },
);

sub should_use ($premium_mult, $policy) {
    my $name = $policy->{name} // 'default';
    my $handler = $POLICIES{$name} or return 0;
    return $handler->($premium_mult, $policy->{params} // {});
}

1;
