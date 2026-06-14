package MagicMountain::Controller::Artifact;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub _activity_action ($self, $action, %params) {
    my $player_id = $self->session('playerId');

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $p   = $self->app->prospecting;
    my $row = $char_model->row;
    my $id  = $row->{pending_activity_id};

    my $activity = $id && $p->get($id)
        ? $p->get($id)
        : $p->create(char_id => $row->{id});

    my $result = $activity->dispatch($row, $action, %params);

    if ($activity->phase eq 'idle') {
        $p->delete($activity->getCol('id'));
        $char_model->setCol('pending_activity_id', undef);
    } else {
        $activity->save;
        $char_model->setCol('pending_activity_id', $activity->getCol('id'));
    }
    $char_model->save;

    $self->render(json => $result->{view});
}

sub begin ($self) { $self->_activity_action('begin') }
sub push  ($self) { $self->_activity_action('push')  }
sub stop  ($self) { $self->_activity_action('stop')  }

1;
