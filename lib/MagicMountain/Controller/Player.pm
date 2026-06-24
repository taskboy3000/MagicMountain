package MagicMountain::Controller::Player;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $format = $self->param('_format');

    if ($format && $format eq 'fragment') {
        my $player_id = $self->current_player;
        return $self->rendered(204) unless $player_id;
        my $season = $self->app->active_season;
        my $season_id = $season ? $season->getCol('id') : undef;
        $self->app->characters->load;
        my ($char) = @{ $self->app->characters->find(
            sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
        ) };
        return $self->rendered(204) unless $char;
        $self->stash(
            player_name => $char->getCol('name') // '—',
            ap          => $char->getCol('action_points') // 0,
            scrap       => $char->getCol('scrap') // 0,
            score       => $char->getCol('score') // 0,
        );
        return $self->render('player/status', layout => undef);
    }

    # JSON: original shape (account-level)
    my $player_id = $self->current_player;
    return $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401)
        unless $player_id;
    my $account = $self->app->accounts->get($player_id);
    $self->render(json => {
        ok => 1,
        player => {
            id          => $player_id,
            displayName => $account->getCol('username'),
        },
    });
}

sub destroy ($self) {
    my $player_id = $self->current_player;
    return $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401)
        unless $player_id;

    $self->app->session_store->delete_by_player_id($player_id);
    $self->session(expires => 1);

    my $chars = $self->app->characters;
    my $existing = $chars->find({ account_id => qr/^\Q$player_id\E$/ });
    for my $char (@$existing) {
        $chars->delete($char->getCol('id'));
    }

    $self->app->accounts->delete($player_id);

    $self->app->audit_log->log('account_deleted', player_id => $player_id);

    $self->render(json => { ok => 1 });
}

1;
