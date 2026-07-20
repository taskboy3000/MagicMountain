package MagicMountain::Bot::SellPolicy;
use Mojo::Base '-base', '-signatures';

my %ACCEPT_CUSTOMER = (
    hoarder          => sub ($cust, $p) { 0 },
    faction_loyalist => sub ($cust, $p) { ($cust->{faction} // '') eq ($p->{faction} // '') },
    default          => sub ($cust, $p) { 1 },
);

my %OFFER_ITEM = (
    highest_offer    => sub ($item, $p) { ($item->{decayed_value} // 0) >= ($p->{min_value} // 10) },
    default          => sub ($item, $p) { 1 },
);

my %TRY_ANOTHER = (
    opportunist      => sub ($offer, $cust, $p) { 0 },
    default          => sub ($offer, $cust, $p) { 1 },
);

my %ACCEPT_COUNTER = (
    default          => sub ($counter_value, $decayed, $p) {
        my $agg = $p->{haggle_aggression};
        return 0 if defined($agg) && !$agg;
        if (defined($agg) && $agg < 1.0) {
            return 0 unless rand() < $agg;
        }
        my $min_pct = $p->{min_counter_pct} // 0;
        return $counter_value >= ($decayed // 0) * $min_pct;
    },
);

sub _dispatch ($name, $table, @args) {
    my $handler = $table->{$name} // $table->{default};
    return $handler->(@args);
}

sub accept_customer ($customer, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%ACCEPT_CUSTOMER, $customer, $policy->{params} // {});
}

sub should_offer_item ($item, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%OFFER_ITEM, $item, $policy->{params} // {});
}

sub try_another ($offer_view, $customer, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%TRY_ANOTHER, $offer_view, $customer, $policy->{params} // {});
}

sub should_accept_counter ($counter_value, $decayed_value, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%ACCEPT_COUNTER, $counter_value, $decayed_value, $policy->{params} // {});
}

1;
