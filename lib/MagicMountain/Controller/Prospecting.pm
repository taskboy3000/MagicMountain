package MagicMountain::Controller::Prospecting;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Artifact;

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    return $self->rendered(204) unless $type && $type eq 'prospecting';

    my $activity = $self->app->prospecting->get($char->getCol('pending_activity_id'));
    return $self->rendered(204) unless $activity && $activity->phase ne 'idle';

    my $pending = $activity->getCol('pending_event');
    if ($pending && $pending->{choices}) {
        my $format = $self->param('_format');
        if ($format && $format eq 'fragment') {
            $self->stash(event_text => $pending->{text}, choices => $pending->{choices});
            return $self->render(inline => <<~'HTML', layout => undef);
              <div class="mm-panel">
                <div class="mm-panel-header">EVENT</div>
                <div class="mm-panel-body">
                  <p class="mm-text-amber" style="font-size:0.72rem;text-transform:uppercase;letter-spacing:0.05em"><%= $event_text %></p>
                  <div class="mm-flex-center" style="gap:0.5rem;margin-top:0.5rem">
                  %= include 'components/action_buttons', actions => $choices
                  </div>
                </div>
              </div>
HTML
        }
        return $self->render(json => {
            ok     => 1,
            event  => {
                id      => $pending->{event_id},
                choices => $pending->{choices},
            },
            _self  => { actions => [] },
        });
    }

    my $artifact = MagicMountain::Artifact->new($activity->artifact);

    my @actions = (
        { label => 'Push', attrs => { 'data-action-url' => '/prospecting/push', 'data-method' => 'POST', id => 'btn-push', class => 'mm-btn mm-btn-primary' } },
        { label => 'Stop', attrs => { 'data-action-url' => '/prospecting/stop', 'data-method' => 'POST', id => 'btn-stop', class => 'mm-btn mm-btn-primary' } },
    );

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(artifact => $artifact, actions => \@actions,
            event => $activity->artifact->{_event_text} ? { text => $activity->artifact->{_event_text} } : undef);
        return $self->render('prospecting/scan', layout => undef);
    }

    $self->render(json => {
        ok          => 1,
        prospecting => $artifact,
        _self       => { actions => \@actions },
    });
}

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

    $self->_render_action($result, 'prospecting_' . $action);
}

sub begin          ($self) { $self->_activity_action('begin') }
sub push           ($self) { $self->_activity_action('push')  }
sub stop           ($self) { $self->_activity_action('stop')  }
sub resolve_event  ($self) { $self->_activity_action('resolve_event', %{ $self->req->json }) }

1;
