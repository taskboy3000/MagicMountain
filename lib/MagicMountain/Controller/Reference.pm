package MagicMountain::Controller::Reference;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $id = $self->param('id') or return $self->rendered(204);
    my $entries = $self->app->references_data;
    my ($entry) = grep { $_->{id} eq $id } @$entries;
    return $self->rendered(204) unless $entry;

    my $display = {
        %$entry,
        icon => $entry->{icon} ? '/images/' . $entry->{icon} : undef,
    };

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(entry => $display);
        return $self->render('reference/show', layout => undef);
    }

    $self->render(json => { ok => 1, entry => $display });
}

1;
