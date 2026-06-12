package MagicMountain::Controller::Game;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;

    my $account = $self->app->accounts->get($player_id);
    $self->stash(player_name => $account->getCol('username'));

    my $seasons = $self->app->seasons;
    $seasons->load;
    my @season_ids = keys %{$seasons->table};
    my $season = @season_ids ? $seasons->table->{$season_ids[0]} : undef;
    $self->stash(
        season_label       => $season ? ($season->{label} // 'Season 1')     : 'Upcoming',
        season_day         => $season ? ($season->{day} // 1)                : '—',
        season_total_days  => $season ? ($season->{length} // 30)            : '—',
        season_is_active   => $season ? 1 : 0,
    );

    $self->render('game/show');
}

1;
