package MagicMountain::Controller::Season;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Model::Season;

sub show ($self) {
    my $season = $self->app->active_season;
    return $self->rendered(204) unless $season;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            day   => $season->getCol('day') // 1,
            total => $season->getCol('length') // 30,
            label => $season->getCol('label') // 'Season',
        );
        return $self->render('season/info', layout => undef);
    }

    $self->render(json => {
        ok           => 1,
        day          => $season->getCol('day') // 1,
        total_days   => $season->getCol('length') // 30,
        label        => $season->getCol('label') // 'Season',
        crier_message => $season->getCol('crier_message'),
    });
}

sub end ($self) {
    MagicMountain::Model::Season->finalize($self->app);
    $self->render(json => { ok => 1, message => 'Season ended.', csrf_token => $self->csrf_token, refetch => [] });
}

1;
