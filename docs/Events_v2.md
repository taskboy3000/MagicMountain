# Magic Mountain — Random Events (v2)

*A lightweight, YAML-driven random event system for prospecting and sales.
Designed as a Service consumed by existing Activities — no new infrastructure,
no event engine, no persistent buffs.*

---

## 1. Design Goals

1. **Transient effects only** — Events modify the current artifact or customer
   at the moment they fire. No persistent modifiers, no buff timers, no new
   character columns. Their effect is baked into the artifact/customer state
   that's already persisted by the Activity.

2. **YAML-driven** — New `content/flavor/events.yml` with two top-level keys:
   `prospecting_events` and `sales_events`. Adding or rebalancing an event is
   a content edit, not a code change.

3. **Minimal new infrastructure** — No event engine, no `content/events/`
   directory, no new model classes. A single Service class
   (`Service::RandomEvents`) that Activities call at action boundaries. The
   only new persistence is a `pending_event` column on the activity row for
   prompt-style events that must survive across HTTP requests.

4. **PB3K framing** — Events appear as device sensor readings, system
   advisories, or environmental readings — never as game-UI "notifications."
   This is consistent with the device-fiction constraint (GAME_ARCHITECTURE.md §1.1).

5. **Decisions over variance** — When possible, events should present the
   player with a lightweight yes/no choice rather than applying an invisible
   modifier. This prevents events from feeling like random noise.

---

## 2. Where Events Fire

| Action Boundary | Event Pool | Integration Point |
|-----------------|------------|-------------------|
| `Prospecting::begin` (after artifact draw, before save) | `prospecting_events` with `trigger: begin` | Drawn artifact is mutated in-place before the activity row is saved. Event text is stored ephemerally and included in the view. |
| `Prospecting::push` (after push math, before save) | `prospecting_events` with `trigger: push` | Artifact state is mutated in-place. Event text included in view alongside signal text. |
| `MarketVisit::begin` (after customer gen, before save) | `sales_events` with `trigger: begin` | Customer hash is mutated in-place. Event text included in view alongside customer intro. |
| `MarketVisit::offer` (after match/mismatch check, before save) | `sales_events` with `trigger: offer` | Offer outcome or irritation is mutated. Event text included in view. |

Events never replace an action — they fire **alongside** the action. The
player always gets the normal outcome (draw, push result, offer result) plus
an optional event overlay.

For events with a `prompt`, the action flow pauses briefly for a single
`{ choice: "accept" | "decline" }` response from the player, then continues
without consuming a turn.

---

## 3. YAML Structure

File: `content/flavor/events.yml`

```yaml
prospecting_events:
  - id: unstable_pocket
    weight: 5
    trigger: begin
    text: "STABILITY WARNING — Localized field distortion. Artifact containment may be compromised."
    effects:
      - adjust_instability: 2

  - id: rich_vein
    weight: 3
    trigger: push
    text: "YIELD ANALYSIS — Unexpected secondary payload detected. Value projection revised upward."
    effects:
      - adjust_value_gain: 3

  - id: containment_leak
    weight: 6
    trigger: push
    condition: artifact_stage_unstable
    text: "CONTAINMENT ALERT — Cascading field collapse in progress. Instability spike detected."
    effects:
      - scale_instability: 1.5

  - id: secondary_signal
    weight: 4
    trigger: begin
    min_day: 3
    text: "ANOMALY DETECTED — Artifact appears to have a secondary behavioral signature."
    effects:
      - add_behavior: "signal"

  - id: mountain_exhales
    weight: 2
    trigger: begin
    max_day: 15
    text: "GEOPHYSICAL EVENT — The mountain vents. A loose artifact surfaces nearby."
    effects:
      - no_ap_cost: 1

  - id: seismic_echo
    weight: 8
    trigger: begin
    min_day: 3
    prompt: "SENSORY ALERT — Low-frequency resonance detected. Dense pocket likely nearby. Push harder?"
    effects:
      - adjust_value: 4
      - adjust_instability: 2

  - id: volatile_readings
    weight: 4
    trigger: push
    condition: artifact_strained
    prompt: "WARNING — Artifact beginning to resonate. Values climbing but instability rising. Continue?"
    effects:
      - adjust_value_gain: 5
      - adjust_instability: 3

sales_events:
  - id: desperate_courier
    weight: 8
    trigger: begin
    condition: faction_days_since_purchase_gte_3
    text: "INCOMING TRANSMISSION — {faction_name} courier dispatching priority procurement. Backlog rates in effect."
    effects:
      - multiplier_bonus: 0.25

  - id: flooded_market
    weight: 5
    trigger: begin
    text: "MARKET ANALYSIS — Elevated supply detected in local inventory. Buyer leverage increased."
    effects:
      - multiplier_penalty: -0.15

  - id: generous_buyer
    weight: 4
    trigger: offer
    condition: outcome_match
    text: "NEGOTIATION LOG — Buyer appears unusually satisfied with the match. Adjusting valuation upward."
    effects:
      - match_premium: 1.15

  - id: thin_skinned
    weight: 4
    trigger: begin
    text: "PSYCH PROFILE — Buyer flagged as irritable. Recommend measured approach."
    effects:
      - irritation_floor: 2

  - id: faction_bounty
    weight: 5
    trigger: begin
    condition: customer_standing_gte_2
    text: "NOTICE — {faction_name} has posted a procurement bonus for repeat partners. Standing recognized."
    effects:
      - standing_bonus_mult: 1.1

  - id: eager_buyer
    weight: 3
    trigger: offer
    condition: offer_mismatch
    prompt: "BUYER NOTE — They don't love the match but are eager to close. Accept reduced rate?"
    effects:
      - match_premium: 0.85
```

### Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `id` | yes | — | Unique identifier for the event |
| `weight` | yes | — | Relative probability (higher = more likely) |
| `trigger` | yes | — | `begin`, `push`, or `offer` |
| `min_day` | no | null | Only fire on or after this season day |
| `max_day` | no | null | Only fire on or before this season day |
| `condition` | no | null | Named condition key (see §3a) — evaluated against context by Perl registry |
| `skill_min` | no | null | Requires character's relevant skill >= this level |
| `skill_max` | no | null | Requires character's relevant skill <= this level |
| `text` | yes | — | Player-facing flavor text (may contain `{placeholder}` substitutions) |
| `prompt` | no | null | If present, player is offered a yes/no choice before effects apply |
| `effects` | yes | — | Array of effect maps (see §4). Applied if no `prompt`, or if player accepts. If player declines, no effects apply. |

### 3a. Condition Registry

Conditions are **not** inline Perl expressions. Each `condition` value is a
named key in a Perl-side dispatch table. This is safer (no eval), more
testable, and more discoverable than stringified code in YAML.

```perl
# MagicMountain::Service::RandomEvents

my $CONDITIONS = {
    artifact_stage_unstable       => sub ($ctx) { $ctx->{artifact}{stage} eq 'unstable' },
    artifact_strained             => sub ($ctx) { $ctx->{artifact}{stage} eq 'strained' },
    outcome_match                 => sub ($ctx) { $ctx->{outcome} eq 'match' },
    offer_mismatch                => sub ($ctx) { $ctx->{outcome} ne 'match' },
    faction_days_since_purchase_gte_3 => sub ($ctx) {
        return 0 unless $ctx->{faction_state} && $ctx->{current_customer};
        my $fs = $ctx->{faction_state}{ $ctx->{current_customer} };
        return ($fs->{days_since_purchase} // 99) >= 3;
    },
    customer_standing_gte_2       => sub ($ctx) {
        return ($ctx->{standing}{ $ctx->{current_customer} } // 0) >= 2;
    },
};

sub _check_condition ($self, $name, $context) {
    my $check = $CONDITIONS->{$name} or return 0;
    return $check->($context);
}
```

Adding a new condition means adding one entry to `$CONDITIONS` and one line
in the test file. No YAML changes needed beyond the event definition.

---

## 4. Effect Types

### Prospecting Effects

| Effect | Arguments | Description |
|--------|-----------|-------------|
| `adjust_value` | integer | Add to artifact `base_value` at draw time |
| `adjust_instability` | integer | Add to artifact `starting_instability` at draw time |
| `adjust_value_gain` | integer | Add to this push's value gain (before skill modifiers) |
| `scale_instability` | float | Multiply artifact's current instability |
| `add_behavior` | string | Append a behavior tag to the artifact |
| `no_ap_cost` | boolean | If true, refund 1 AP on this action |

### Sales Effects

| Effect | Arguments | Description |
|--------|-----------|-------------|
| `multiplier_bonus` | float | Add to the effective offer multiplier |
| `multiplier_penalty` | float | Subtract from the effective offer multiplier |
| `match_premium` | float | Multiply match offers by this factor |
| `irritation_floor` | integer | Starting irritation (customer starts more irritated) |
| `irritation_ceiling` | integer | Max irritation before storm-off (customer more/less patient) |
| `standing_bonus_mult` | float | Extra multiplier based on standing with this faction |

Effect arguments are content-defined. The Service applies them to the
activity's current state (artifact or customer hashref) before the
activity's main logic continues.

---

## 5. Service: `MagicMountain::Service::RandomEvents`

### Data loading

Events YAML is loaded via an app helper, matching the existing pattern used
by `skills_data`, `factions_data`, and `advisories`:

```perl
# MagicMountain.pm startup:
$self->helper(events_data => sub ($c) {
    state $data = YAML::XS::LoadFile($c->app->home . '/content/flavor/events.yml');
    return $data;
});
```

### Construction

The Service receives the parsed data at construction time (not a file path),
consistent with how `SkillTraining` and `Navigation` receive their
dependencies:

```perl
# MagicMountain.pm startup:
has random_events => sub ($self) {
    MagicMountain::Service::RandomEvents->new(
        app  => $self,
        data => $self->events_data,
    );
};
```

### API

```perl
# Draw an event from the pool, return undef if none fire
my $event = $self->app->random_events->draw(
    pool   => 'prospecting',    # or 'sales'
    char   => $char,            # Model::Character
    context => {                # action-specific state
        artifact         => $artifact,
        customer         => $customer,
        season           => $season,
        standing         => \%standing,
        faction_state    => \%faction_state,
        current_customer => $customer->{faction},
        outcome          => $outcome,
    },
);

if ($event) {
    if ($event->{prompt}) {
        # Store for choice resolution across HTTP requests.
        # Persisted as a JSON `pending_event` column on the activity row.
        $self->setCol('pending_event', { event => $event, context => $context });
    } else {
        $self->app->random_events->apply_effects($event, $context);
    }
}
```

Effect application is a method on the Service, keeping it as the sole owner
of event mechanics:

```perl
sub apply_effects ($self, $event, $context) {
    for my $effect (@{ $event->{effects} // [] }) {
        my ($type, $arg) = each %$effect;
        ...
    }
}
```

For events with a `prompt`, the Activity stores the pending event in a
`pending_event` column on the activity row (serialized as a JSON object).
This survives across HTTP requests. The player sends
`{ choice: "accept" | "decline" }` via a follow-up endpoint. If accepted,
effects are applied via the Service; if declined, nothing happens. Either
way, the pending event is cleared.

### Selection Algorithm

1. Filter pool by `trigger` matching the current action
2. Filter by `min_day` / `max_day` against `season.day`
3. Filter by `skill_min` / `skill_max` against character's relevant skill
4. Evaluate `condition` via the named condition registry
5. If no events remain, return undef
6. Weighted random selection from remaining events
7. Return the selected event (or undef if none match)

The Service also exposes `pool_size($pool, $context)` for testing — returns
count of eligible events after all filters.

### View Integration

The Activity includes event data in its view hashref:

```perl
{
    view => {
        ok      => 1,
        result  => 'push',
        artifact => { ... },
        event   => {
            id   => 'containment_leak',
            text => 'CONTAINMENT ALERT — Cascading field collapse...',
        },
    },
}
```

For events with a `prompt`, the view additionally includes `event.prompt`
and the player must respond with a choice before the action fully resolves:

```perl
{
    view => {
        ok      => 1,
        result  => 'push',
        artifact => { ... },
        event   => {
            id     => 'volatile_readings',
            text   => 'WARNING — Artifact beginning to resonate...',
            prompt => 'Continue pushing?',
        },
    },
}
```

The player sends `POST /prospecting/event_choice { choice: "accept" }` or
`{ choice: "decline" }`. Both paths resolve the action; only "accept"
applies effects.

### Transition Routing

`event_choice` is added to every non-idle phase's transition list so the
Activity's dispatch mechanism handles it:

```perl
# Prospecting
has transitions => sub { { idle => ['begin'], processing => ['push', 'stop', 'event_choice'] } };

# MarketVisit
has transitions => sub { { idle => ['begin'], negotiating => ['offer', 'send_away', 'event_choice'] } };
```

Although `event_choice` is not a state-machine transition, listing it
explicitly keeps routing consistent with all other actions and prevents
surprise when new developers read the transition table.

### Prompt Resolution: Controller and Activity Handlers

Each activity controller gains a single thin endpoint for resolving prompts:

- `POST /prospecting/event_choice`
- `POST /market/event_choice`

**Controller** (thin pipe — extracts params, invokes Activity, renders):

```perl
# Controller::Prospecting
sub event_choice ($self) {
    my $char = $self->current_player;
    my $choice = $self->req->json->{choice} // '';
    die "invalid choice" unless $choice eq 'accept' || $choice eq 'decline';
    my $activity = $self->_load_activity($char);
    my $view = $activity->dispatch($char, 'event_choice', choice => $choice);
    $self->render(json => $view);
}
```

**Activity handler** (owns all resolution logic):

```perl
# Activity::Prospecting
sub event_choice ($self, $char, %params) {
    my $pending = $self->getCol('pending_event') or die "no pending event";
    if ($params{choice} eq 'accept') {
        $self->app->random_events->apply_effects($pending->{event}, $pending->{context});
    }
    $self->setCol('pending_event', undef);
    $self->save;
    return { view => { ok => 1, result => 'event_resolved', ... } };
}
```

This keeps the controller as a dumb pipe (reads JSON, calls dispatch,
renders) and the Activity as the owner of state mutations — matching the
existing controller boundary convention (AGENTS.md, Controller Boundaries).

No separate endpoint is needed for each event type — the choice resolution
is generic and data-driven.

---

## 6. World Feedback — DEFERRED

The Crier integration (daily event log, pattern detection, event-based crier
messages) described in the v1 spec is **deferred**. The event service will
be implemented and playtested first. World-feedback patterns will only be
added after events feel good in actual gameplay.

Future implementation may include:
- An aggregate event log on the Season model
- Pattern detection in the maintenance callback
- New crier message categories for event-driven narrative

---

## 7. Bot Integration

Bot policies need no changes. The event service fires automatically during
the Activity's `dispatch`, which bots call identically to human players.
Event flavor text is simply discarded by the bot's response handler — the
mechanical effect is already applied.

For prompted events, bots always respond with `decline` (conservative
default) unless a future bot profile option specifies otherwise.

---

## 8. Testing Strategy

| Test | What It Covers |
|------|----------------|
| `t/random_events.t` | Service unit tests: YAML loading, pool filtering, weighted selection, effect application, condition registry |
| `t/prospecting_events.t` | Integration: events fire during `begin`/`push`, artifact is mutated, view includes event text |
| `t/sales_events.t` | Integration: events fire during `begin`/`offer`, customer is mutated, view includes event text |
| `t/prompt_events.t` | Prompt flow: event with prompt stores pending event, choice resolves correctly |
| `t/prospecting_web.t` / `t/market_visit_web.t` | Fragment rendering: event text appears in HTML, styled as advisory |
| `bin/smoke_test_endpoint` | No new endpoints needed — events piggyback on existing action responses |

---

## 9. Comparison with Existing Events Design

The existing `docs/Events.md` describes a heavier system with choice-based
interrupt events, an event engine, and turn-consuming events. The design
here is intentionally simpler:

| Concern | Existing Design (docs/Events.md) | This Design |
|---------|----------------------------------|-------------|
| Infrastructure | Event engine class, content/events/ dir, State mutations | Single Service, one YAML file, one new activity column (`pending_event`) |
| Player interaction | Choice-based (multiple outcomes) | Passive or simple yes/no prompt |
| Turn economy | Interrupts consume a prospecting turn | No turn cost (fires alongside action) |
| Persistence | Outcome mutations on State | Transient — effect baked into existing persisted state |
| World feedback | Unspecified | Deferred (see §6) |

Both designs could coexist: the lightweight system here handles the
"ambient atmosphere + small mechanical surprise" slot. The heavier choice
system (if implemented later) would handle structured narrative events.
