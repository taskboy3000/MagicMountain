package MagicMountain::Controller::Leaderboard;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub index ($self) {
    my $season = $self->app->active_season;
    return $self->render(json => { ok => 0, error => 'No active season' }, status => 404)
        unless $season;

    $self->app->characters->load;
    my $chars = $self->app->characters->find(
        sub { $_[0]->{season_id} eq $season->getCol('id') }
    );

    my @sorted = sort { $b->getCol('score') <=> $a->getCol('score') } @$chars;
    my @ranked;
    for my $i (0 .. $#sorted) {
        push @ranked, {
            rank  => $i + 1,
            name  => $sorted[$i]->getCol('name'),
            score => $sorted[$i]->getCol('score') // 0,
        };
    }

    $self->render(json => { ok => 1, leaderboard => \@ranked });
}

1;
