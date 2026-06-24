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

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(entries => \@ranked);
        return $self->render('leaderboard/rankings', layout => undef);
    }

    $self->render(json => { ok => 1, leaderboard => \@ranked });
}

sub factions ($self) {
    my $season = $self->app->active_season;
    return $self->render(json => { ok => 0, error => 'No active season' }, status => 404)
        unless $season;

    my $snaps = $self->app->faction_snapshots->find(
        sub { $_[0]->{season_id} eq $season->getCol('id') }
    );

    my %by_faction;
    for my $s (@$snaps) {
        push @{ $by_faction{ $s->getCol('faction_id') } }, {
            day                => $s->getCol('day'),
            influence          => $s->getCol('influence'),
            artifacts_received => $s->getCol('artifacts_received'),
        };
    }

    $self->render(json => { ok => 1, factions => \%by_faction });
}

1;
