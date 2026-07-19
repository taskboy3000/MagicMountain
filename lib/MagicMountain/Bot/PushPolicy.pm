package MagicMountain::Bot::PushPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    fixed_pushes    => sub ($art, $p) { ($art->{push_count} // 0) >= ($p->{max} // 3) },
    instability_cap => sub ($art, $p) { ($art->{instability} // 0) > ($p->{max} // 5) },
    stage_guard     => sub ($art, $p) { ($art->{stage} // '') eq ($p->{stop_at} // 'unstable') },
    greed           => sub ($art, $p) { rand() >= ($p->{prob} // 0.7) },
    value_target    => sub ($art, $p) { ($art->{value} // 0) >= ($p->{min} // 20) },
    composite_and   => sub ($art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 0 unless __PACKAGE__->evaluate($art, $sub);
        }
        return 1;
    },
    composite_or    => sub ($art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 1 if __PACKAGE__->evaluate($art, $sub);
        }
        return 0;
    },
);

sub evaluate ($artifact, $policy) {
    my $name = $policy->{name} or die "push policy missing name";
    my $handler = $POLICIES{$name} or die "unknown push policy: $name";
    my $should_stop = $handler->($artifact, $policy->{params} // {});
    return $should_stop;
}

1;
