package MagicMountain::Controller::Idle;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) if $type;

    my $ap = $char->getCol('action_points') // 0;
    my $shed_count = scalar @{ $self->app->shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') }) };

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            can_prospect => $ap >= 2,
            can_market   => $ap >= 1 && $shed_count > 0,
            has_items    => $shed_count > 0,
            ap           => $ap,
        );
        return $self->render('idle/actions', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        can_prospect => $ap >= 2,
        can_market  => $ap >= 1 && $shed_count > 0,
        shed_count  => $shed_count,
        _self       => { actions => [] },
    });
}

1;
