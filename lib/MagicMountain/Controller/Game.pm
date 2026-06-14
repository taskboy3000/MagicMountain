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

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id }
    ) };
    if ($char_model) {
        my $row = $char_model->row;
        $self->stash(
            score           => $row->{score} // 0,
            scrap           => $row->{scrap} // 0,
            turns_remaining => $row->{turns_remaining} // 0,
        );

        my $id = $row->{pending_activity_id};
        if ($id) {
            my $activity = $self->app->prospecting->get($id);
            if ($activity) {
                if ($activity->phase ne 'idle') {
                    $self->stash(
                        active_phase  => $activity->phase,
                        artifact_json => $self->_json($activity->artifact),
                        offers_json   => $self->_json($activity->offers),
                    );
                }
            }
        }
    } else {
        $self->stash(score => 0, scrap => 0, turns_remaining => 0);
    }

    $self->render('game/show');
}

sub _json ($self, $data) {
    return 'null' unless defined $data;
    require Mojo::JSON;
    Mojo::JSON::encode_json($data);
}

1;
