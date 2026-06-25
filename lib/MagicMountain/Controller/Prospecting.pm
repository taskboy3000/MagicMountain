package MagicMountain::Controller::Prospecting;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) unless $type && $type eq 'prospecting';

    my $activity = $self->app->prospecting->get($char->getCol('pending_activity_id'));
    return $self->rendered(204) unless $activity && $activity->phase ne 'idle';

    my $a = $activity->artifact;

    my @actions = (
        { label => 'Push', attrs => { 'data-action-url' => '/prospecting/push', 'data-method' => 'POST', id => 'btn-push', class => 'mm-btn mm-btn-primary' } },
        { label => 'Stop', attrs => { 'data-action-url' => '/prospecting/stop', 'data-method' => 'POST', id => 'btn-stop', class => 'mm-btn' } },
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            artifact_id    => $a->{id},
            stage          => $a->{stage},
            value          => $a->{value},
            signal         => $a->{signal},
            intro          => $a->{intro},
            instability    => $a->{instability},
            max_instability => $a->{max_instability},
            actions        => \@actions,
        );
        return $self->render('prospecting/scan', layout => undef);
    }

    $self->render(json => {
        ok     => 1,
        prospecting => {
            id     => $a->{id},
            stage  => $a->{stage},
            value  => $a->{value},
            signal => $a->{signal},
            intro  => $a->{intro},
        },
        _self => { actions => \@actions },
    });
}

sub _activity_action ($self, $action, %params) {
    my $player_id = $self->session('playerId');
    my $season = $self->app->active_season;
    my $season_id = $season ? $season->getCol('id') : undef;

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $p   = $self->app->prospecting;
    my $id  = $char_model->getCol('pending_activity_id');

    my $activity = $id
        ? $p->get($id)
        : $p->create(char_id => $char_model->getCol('id'));

    my $result = $activity->dispatch($char_model, $action, %params);

    $self->_render_action($result, 'prospecting_' . $action);
}

sub begin ($self) { $self->_activity_action('begin') }
sub push  ($self) { $self->_activity_action('push')  }
sub stop  ($self) { $self->_activity_action('stop')  }

1;
