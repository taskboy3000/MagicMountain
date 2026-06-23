package MagicMountain::Bot::SellPolicy;
use Mojo::Base '-base', '-signatures';

my %ACCEPT_CUSTOMER = (
    hoarder          => sub ($char, $cust, $p) { 0 },
    faction_loyalist => sub ($char, $cust, $p) { ($cust->{faction_id} // '') eq ($p->{faction} // '') },
    default          => sub ($char, $cust, $p) { 1 },
);

my %OFFER_ITEM = (
    highest_offer    => sub ($char, $item, $p) { ($item->getCol('decayed_value') // 0) >= ($p->{min_value} // 10) },
    default          => sub ($char, $item, $p) { 1 },
);

my %TRY_ANOTHER = (
    opportunist      => sub ($char, $offer, $cust, $p) { 0 },
    default          => sub ($char, $offer, $cust, $p) { 1 },
);

my %ACCEPT_COUNTER = (
    highest_offer    => sub ($char, $counter_value, $decayed, $p) { 0 },
    default          => sub ($char, $counter_value, $decayed, $p) {
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

sub accept_customer ($char, $customer, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%ACCEPT_CUSTOMER, $char, $customer, $policy->{params} // {});
}

sub should_offer_item ($char, $item, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%OFFER_ITEM, $char, $item, $policy->{params} // {});
}

sub try_another ($char, $offer_view, $customer, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%TRY_ANOTHER, $char, $offer_view, $customer, $policy->{params} // {});
}

sub should_accept_counter ($char, $counter_value, $decayed_value, $policy) {
    my $name = $policy->{name} // 'default';
    _dispatch($name, \%ACCEPT_COUNTER, $char, $counter_value, $decayed_value, $policy->{params} // {});
}

1;
