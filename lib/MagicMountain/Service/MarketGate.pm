package MagicMountain::Service::MarketGate;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub should_route_to_black_market ($self, $char) {
    my $season = $self->app->active_season or return 0;
    my $climate = $season->getCol('faction_climate') // {};
    my @banned = @{ $climate->{banned_traits} // [] };
    return 0 unless @banned;
    return 0 if $char->getCol('black_market_opportunity_offered_today');
    return 0 if $char->getCol('pending_activity_id');
    return 0 if ($char->getCol('action_points') // 0) < 1;

    my $items = $self->app->shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
    for my $item (@$items) {
        my $behaviors = $item->getCol('behaviors') // [];
        for my $b (@banned) {
            return 1 if grep { $_ eq $b } @$behaviors;
        }
    }
    return 0;
}

1;
