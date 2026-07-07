package MagicMountain::Controller::Home;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::Suggestion;

sub show ($self) {
    my $char = $self->_require_character or return;

    my $season     = $self->app->active_season;
    my $season_day = $season ? $season->getCol('day') // 1 : 1;

    my $all_shed = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );
    my $shed_count = scalar @$all_shed;

    my $type = $self->_active_activity_type($char);
    my $market_active = ($type && $type eq 'market') ? 1 : 0;

    my $advisories = $self->app->advisories // {};
    my $svc = MagicMountain::Service::Suggestion->new(app => $self->app);
    my $suggestions = $svc->build($char, $season, $advisories, $all_shed);

    my $crier = $season ? $season->getCol('crier_message') : undef;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my $skill = $char->getCol('skill_prospecting') // 0;
        my @shed_rows;
        for my $item (@$all_shed) {
            my $aid = $item->getCol('artifact_id');
            my $behaviors = $item->getCol('behaviors') // [];
            push @shed_rows, {
                id          => $item->getCol('id'),
                label       => $aid,
                label_full  => $aid,
                icon        => '/images/artifact_' . $aid . '.svg',
                condition   => $item->getCol('condition'),
                value_label => $item->value_label,
                days        => $item->getCol('days_in_shed'),
                behaviors   => $behaviors,
                tags        => $skill >= 1 ? join(', ', @$behaviors) : '-',
            };
        }
        my $fresh_player = !$type && !$shed_count && !$char->getCol('scrap');
        my $fc = $season ? $season->faction_climate : {};
        my $biases = $fc->{market}{buyer_trait_biases} // {};
        $self->stash(
            suggestions              => $suggestions,
            season_day               => $season_day,
            season_len               => $season ? $season->getCol('length') // 30 : 30,
            ap                       => $char->getCol('action_points') // 0,
            scrap                    => $char->getCol('scrap') // 0,
            shed_count               => $shed_count,
            shed_items               => \@shed_rows,
            market_active            => $market_active,
            crier_msg                => $crier,
            fresh_player             => $fresh_player,
            faction_climate          => $fc,
            climate_premium_traits   => [ sort keys %$biases ],
            show_trait_tags          => $skill >= 1 ? 1 : 0,
        );
        return $self->render('home/dashboard', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        suggestions => $suggestions,
        crier       => $crier,
    });
}

1;
