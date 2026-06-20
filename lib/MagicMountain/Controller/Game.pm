package MagicMountain::Controller::Game;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;

    my $account = $self->app->accounts->get($player_id);
    $self->stash(player_name => $account->getCol('username'));

    $self->app->seasons->load;
    my $season = $self->app->seasons->find(sub { ($_[0]->{status} // '') eq 'active' });
    $season = @$season ? $season->[0] : undef;
    $self->stash(
        season_label      => $season ? ($season->getCol('label') // 'Season 1') : 'Upcoming',
        season_day        => $season ? ($season->getCol('day') // 1)             : '—',
        season_total_days => $season ? ($season->getCol('length') // 30)         : '—',
        season_is_active  => $season ? 1 : 0,
    );

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season || $_[0]->{season_id} eq $season->getCol('id')) }
    ) };

    unless ($char_model) {
        my $daily_turns = $self->app->config->{default_daily_turns} // 10;
        $char_model = $self->app->characters->create(
            name       => $account->getCol('username'),
            account_id => $player_id,
            season_id  => $season ? $season->getCol('id') : undef,
            score      => 0,
            scrap      => 0,
            turns_remaining => $season ? $daily_turns : 0,
            pending_activity_id => undef,
        );
        $char_model->save;
    }

    {
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
    }

    $self->render('game/show');
}

sub _json ($self, $data) {
    return 'null' unless defined $data;
    require Mojo::JSON;
    Mojo::JSON::encode_json($data);
}

1;
