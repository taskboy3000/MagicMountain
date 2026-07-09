package MagicMountain::Controller::Orientation;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(dismiss_url => $self->url_for('orientation_dismiss'));
        return $self->render('orientation/show', layout => undef);
    }
    $self->render(json => { ok => 1 });
}

sub dismiss ($self) {
    my $player_id = $self->current_player;
    if ($player_id) {
        my ($char_model) = @{ $self->app->characters->find(
            sub { $_[0]->{account_id} eq $player_id }
        ) };
        if ($char_model) {
            $char_model->setCol('seen_orientation', 1);
            $char_model->save;
        }
    }
    $self->render(json => { ok => 1 });
}

1;
