package MagicMountain::Controller::Account;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;
    return $self->rendered(204) unless $player_id;

    my @actions = (
        { label => 'LOGOUT', attrs => { 'data-action-url' => '/sessions', 'data-method' => 'DELETE', id => 'logout-btn', class => 'mm-btn', 'data-redirect' => '/game' } },
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(actions => \@actions);
        return $self->render('account/settings', layout => undef);
    }

    $self->render(json => { ok => 1, _self => { actions => \@actions } });
}

1;
