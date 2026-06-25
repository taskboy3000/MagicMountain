package MagicMountain::Controller::Account;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;
    return $self->rendered(204) unless $player_id;

    my @actions = ({ label => 'Delete Account', attrs => { 'data-action-url' => '/player', 'data-method' => 'DELETE', id => 'delete-account-btn', class => 'mm-btn mm-btn-danger', 'data-confirm' => 'Delete your account permanently? This cannot be undone.', 'data-redirect' => '/login' } });

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(actions => \@actions);
        return $self->render('account/settings', layout => undef);
    }

    $self->render(json => { ok => 1, _self => { actions => \@actions } });
}

1;
