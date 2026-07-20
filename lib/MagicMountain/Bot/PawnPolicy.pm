package MagicMountain::Bot::PawnPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    always => sub ($item, $state, $p) {
        return 'offer';
    },
    value_threshold => sub ($item, $state, $p) {
        return ($item->{decayed_value} // 0) >= ($p->{min_value} // 10) ? 'offer' : 'skip';
    },
    stop_after_seizure => sub ($item, $state, $p) {
        return 'stop' if ($state->{consecutive_seizures} // 0) >= ($p->{max_seizures} // 1);
        return 'offer';
    },
    composite_and => sub ($item, $state, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 'skip' unless @subs;
        for my $sub (@subs) {
            my $d = MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $sub);
            return $d if $d eq 'skip' || $d eq 'stop';
        }
        return 'offer';
    },
    composite_or => sub ($item, $state, $p) {
        my @subs = @{ $p->{policies} // [] };
        for my $sub (@subs) {
            my $d = MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $sub);
            return $d if $d eq 'offer';
        }
        return 'skip';
    },
);

sub evaluate ($item, $state, $policy) {
    my $name = $policy->{name} or return 'offer';
    my $handler = $POLICIES{$name} or return 'offer';
    return $handler->($item, $state, $policy->{params} // {});
}

1;
