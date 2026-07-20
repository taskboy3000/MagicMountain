package MagicMountain::Controller::Pawn;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);

    my $calc = $self->app->pawn_calculator;
    my $has_banned = $calc->has_banned_items($char);

    # If no pawn activity and no banned items, show closed state
    if ((!$type || $type ne 'pawn') && !$has_banned) {
        my $format = $self->param('_format');
        if ($format && $format eq 'fragment') {
            $self->stash(pawn_closed => 1, layout => undef);
            return $self->render('pawn/broker', layout => undef);
        }
        $self->render(json => {
            ok          => 1,
            pawn_closed => 1,
            message     => 'The pawn shop is closed.',
        });
        return;
    }

    # Load activity if in a pawn session
    my $deal;
    if ($type && $type eq 'pawn') {
        my $id = $char->getCol('pending_activity_id');
        my $activity = $self->app->pawn->get($id);
        $deal = $activity ? $activity->customer : undef;
    }

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            pawn_deal => $deal,
            char      => $char,
            layout    => undef,
        );
        return $self->render('pawn/broker', layout => undef);
    }

    $self->render(json => {
        ok   => 1,
        deal => $deal,
    });
}

sub _activity_action ($self, $action, %params) {
    my $char = $self->_require_character or return;
    my $pawn = $self->app->pawn;

    my $id = $char->getCol('pending_activity_id');
    my $activity;
    if ($id) {
        $self->app->prospecting->load;
        my $row = $self->app->prospecting->get($id);
        if ($row && $row->getCol('type') eq 'pawn') {
            $activity = $pawn->get($id);
        }
    }
    $activity //= $pawn->create(char_id => $char->getCol('id'));

    my $result = eval { $activity->dispatch($char, $action, %params) };
    if (my $err = $@) {
        $self->app->log->error(sprintf("Pawn %s error: %s", $action, $err));
        return $self->render(json => { ok => 0, error => $err }, status => 409);
    }

    $self->_render_action($result, 'pawn_' . $action);
}

sub offer      ($self) { $self->_activity_action('offer',      %{ $self->req->json }) }
sub dismiss    ($self) { $self->_activity_action('dismiss') }
sub offer_next ($self) { $self->_activity_action('offer_next') }

1;
