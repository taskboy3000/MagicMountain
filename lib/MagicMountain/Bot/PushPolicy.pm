package MagicMountain::Bot::PushPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    fixed_pushes    => sub ($char, $art, $p) { ($art->{push_count} // 0) >= ($p->{max} // 3) },
    instability_cap => sub ($char, $art, $p) { ($art->{instability} // 0) > ($p->{max} // 5) },
    stage_guard     => sub ($char, $art, $p) { ($art->{stage} // '') eq ($p->{stop_at} // 'unstable') },
    greed           => sub ($char, $art, $p) { rand() >= ($p->{prob} // 0.7) },
    value_target    => sub ($char, $art, $p) { ($art->{value} // 0) >= ($p->{min} // 20) },
    composite_and   => sub ($char, $art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 0 unless __PACKAGE__->evaluate($char, $art, $sub);
        }
        return 1;
    },
    composite_or    => sub ($char, $art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 1 if __PACKAGE__->evaluate($char, $art, $sub);
        }
        return 0;
    },
);

sub evaluate ($char, $artifact, $policy) {
    my $name = $policy->{name} or die "push policy missing name";
    my $handler = $POLICIES{$name} or die "unknown push policy: $name";
    my $should_stop = $handler->($char, $artifact, $policy->{params} // {});
    return $should_stop;
}

1;
