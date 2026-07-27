# Controllers — Module Boundary Rules

> The Engine.pm coordinator class has been removed. Controllers are thin
> adapters between HTTP and the activity system. This file captures the
> invariants previously enforced by Engine.

## Responsibilities
- Extract player identity from session (`$c->current_player`)
- Load character model via `Model::Character`
- Delegate to activity: `$activity->dispatch($char, $action, %params)`
- Pipe `$result->{view}` to the template — no inspection, no filtering

## Constraints (MUST NOT)
- NEVER create accounts. Account creation belongs to Controller::Sessions.
- NEVER apply daily rollover or advance the season clock. That is the
  maintenance callback's job.
- NEVER validate activity phases or check `pending_activity`. The activity
  base class enforces transition legality.
- NEVER call persistence for game-state mutations (AP, scrap, score, shed items,
  activity rows). The activity handles `$char->save` for game state.
- NEVER create or delete activity rows. Activity lifecycle belongs to the
  activity system.
- NEVER orchestrate multi-model persistence (e.g. delete all characters + account
  in one action). Delegate to a service.
- Controllers MAY call `$char->save` for UI-preference/display-state columns
  only: `current_view`, `seen_orientation`, `settings_muted`, `pending_notices`.
  These have no game-mechanical effect and no activity covers them.
- NEVER generate offers or apply sale effects. Market and the activity
  handle this.
- NEVER record transcript events. The activity enriches the transcript;
  the app class owns its lifecycle.
- NEVER inspect or filter the activity's `view` hashref — pipe it verbatim.
- NEVER construct characters (created by join-season flow or maintenance).

## Activity Creation (MUST)
- To start a new activity, call `$activity_model->begin_activity($char, %params)`
  on the activity model (e.g. `$self->app->prospecting->begin_activity($char)`).
  This handles create-or-get + dispatch in one call.
- NEVER call `->create()` on an activity model directly from a controller.
  Activity row creation belongs inside `begin_activity()`.

## Game Rules in Controllers (MUST)
- Controllers MAY compute game-rule checks (AP thresholds, shed requirements)
  and pass the results as precomputed data to services. This is the controller's
  job — it bridges HTTP input to service calls.
- NEVER pass raw character state to a service and let the service re-encode
  game rules. The controller computes the rules; the service applies them.

## Controller Action Pattern

```perl
sub action_name ($self) {
    my $player_id = $self->current_player;

    my $char_model = $self->app->characters->find(
        sub { $_->{account_id} eq $player_id }
    );
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $char = $char_model;

    my $result = $self->app->prospecting->dispatch($char, $action, %params);

    $self->render(json => $result->{view});
}
```

## Activity Construction

One instance per activity type, constructed at startup, reused for all requests.

```perl
# In MagicMountain.pm startup:
$self->helper(prospecting => sub { MagicMountain::Activity::Prospecting->new(
    app     => $self,
    content => $self->content,
    log     => $self->log,
    # NEVER add: characters model, market, transcript
)});
```

**Principle**: Controllers are dumb pipes. Activities own game logic,
persistence, transcript enrichment, and the view contract.
