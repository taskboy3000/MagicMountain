package MagicMountain::Controller::Sale;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub create ($self) {
    my $player_id = $self->session('playerId');

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $p   = $self->app->prospecting;
    my $row = $char_model->row;
    my $id  = $row->{pending_activity_id};

    return $self->render(json => { ok => 0, error => 'No active activity' }, status => 400)
        unless $id;

    my $activity = $p->get($id);
    return $self->render(json => { ok => 0, error => 'Activity not found' }, status => 404)
        unless $activity;

    my $faction_id = $self->param('faction_id');
    return $self->render(json => { ok => 0, error => 'faction_id is required' }, status => 400)
        unless $faction_id;

    my $result = $activity->dispatch($row, 'sell', faction_id => $faction_id);

    $p->delete($activity->getCol('id'));
    $char_model->setCol('pending_activity_id', undef);
    $char_model->save;

    $self->render(json => $result->{view});
}

1;
