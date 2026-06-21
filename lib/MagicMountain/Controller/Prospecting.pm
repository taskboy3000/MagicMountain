package MagicMountain::Controller::Prospecting;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

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

    $self->render(json => $result->{view});
}

sub begin ($self) { $self->_activity_action('begin') }
sub push  ($self) { $self->_activity_action('push')  }
sub stop  ($self) { $self->_activity_action('stop')  }

1;
