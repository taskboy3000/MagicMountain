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
    my $suggestions = $svc->build($char, $season, $advisories, $shed_count);

    my $crier = $season ? $season->getCol('crier_message') : undef;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my @shed_rows;
        for my $item (@$all_shed) {
            my $aid = $item->getCol('artifact_id');
            push @shed_rows, {
                id         => $item->getCol('id'),
                label      => $aid,
                label_full => $aid,
                icon       => '/images/artifact_' . $aid . '.svg',
                condition  => $item->getCol('condition'),
                value_min  => $item->getCol('estimated_value_min'),
                value_max  => $item->getCol('estimated_value_max'),
                days       => $item->getCol('days_in_shed'),
                behaviors  => $item->getCol('behaviors'),
            };
        }
        $self->stash(
            suggestions   => $suggestions,
            season_day    => $season_day,
            season_len    => $season ? $season->getCol('length') // 30 : 30,
            ap            => $char->getCol('action_points') // 0,
            scrap         => $char->getCol('scrap') // 0,
            shed_count    => $shed_count,
            shed_items    => \@shed_rows,
            market_active => $market_active,
            crier_msg     => $crier,
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
