package MagicMountain::Controller::Season;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Model::Season;

sub end ($self) {
    MagicMountain::Model::Season->finalize($self->app);
    $self->render(json => { ok => 1, message => "Season ended." });
}

1;
