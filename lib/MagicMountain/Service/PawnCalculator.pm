package MagicMountain::Service::PawnCalculator;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub premium_multiplier ($self) {
    my @tiers = (2.0, 2.5, 3.0, 3.5);
    return $tiers[int(rand(scalar @tiers))];
}

sub seizure_chance ($self, $decayed_value) {
    my $chance = 0.05 + ($decayed_value / 200) * 0.30;
    return $chance > 0.35 ? 0.35 : $chance;
}

sub apply_smuggling ($self, $char, $chance) {
    my $skill = $char->getCol('skill_smuggling') // 0;
    my $reduced = $chance - $skill * 0.05;
    return $reduced < 0.02 ? 0.02 : $reduced;
}

sub banned_trait_lookup ($self) {
    my $season = $self->app->active_season or return {};
    my $climate = $season->getCol('faction_climate') // {};
    my @banned = @{ $climate->{banned_traits} // [] };
    return +{ map { $_ => 1 } @banned };
}

sub has_banned_items ($self, $char) {
    my $lookup = $self->banned_trait_lookup;
    return 0 unless keys %$lookup;
    my $items = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );
    for my $item (@$items) {
        my $behaviors = $item->getCol('behaviors') // [];
        for my $b (@$behaviors) {
            return 1 if $lookup->{$b};
        }
    }
    return 0;
}

1;
