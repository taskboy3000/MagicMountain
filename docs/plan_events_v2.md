# Implementation Plan: Random Events v2

> Derived from `docs/proposal_events_v2.md`. Delete this file after all phases
> are committed.

---

## Phase Dependency Graph

```
Phase 1: Service skeleton + passive prospecting events
    └── Phase 2: Choice events (prospecting)
            └── Phase 3: Market visit events
    └── Phase 4: Global events + Crier
    └── Phase 5: Content population + docs
```

Phases 3 and 4 are independent of Phase 2 and of each other. Phase 5 depends
on all prior phases.

---

## Phase 1: Service Skeleton + Passive Prospecting Events

**Goal**: A player can prospect, and sometimes a passive event fires. Event
text appears in the response. No choices yet, no market events, no global
events.

### 1.1 Create `Service::RandomEvents`

**File**: `lib/MagicMountain/Service/RandomEvents.pm`

Skeleton:

```perl
package MagicMountain::Service::RandomEvents;
use Modern::Perl;
use Mojo::Base -base, -signatures;

has app => undef;

# Per-pool condition registries. Each key maps to { label, value_type,
# accepts, bounds, handler }.
has conditions => sub { +{
    prospecting => { ... },
} };

# Per-pool effect registries. Same metadata shape plus pool restriction
# for effects like score_delta.
has effects => sub { +{
    prospecting => { ... },
} };

# Config: per-pool per-trigger probability of any event firing.
# YAML weights control which event; this controls whether any event fires.
has event_chance => sub { +{
    prospecting => { begin => 0.20 },
    market_visit => { begin => 0.15 },
} };

has global_event_chance => 0.60;
```

**Key methods:**

- `draw($pool, $trigger, $context, $seeded_rng?)` → event object or undef
  - **Personal pools**: Applies effects immediately inside `draw()`. Returns event
    object with `{ id, text }` for the view.
  - **Global pool**: Rolls, selects, but does NOT apply effects. Returns event
    object; caller must call `$event->apply($context)` separately.
- `apply_choice($pool, $choice_id, $context, $pending_event)` → applies chosen effects
  through handler registry. Used by `resolve_event` action.
- `_select($pool, $trigger, $context)` → selected event definition or undef
- `_evaluate_conditions($event, $pool, $context)` → boolean
- `_resolve_value($raw, $spec, $rng?)` → resolved scalar
- `load($pool)` → validated event list (called at startup)
- `_validate_*` family of private methods

**`draw()` algorithm:**

```
1. Roll rand() < event_chance->{$pool}{$trigger}. Return undef if fail.
2. _select($pool, $trigger, $context)
3. If undef, return undef.
4. Apply each effect in order (range-resolve → validate → call handler).
5. Resolve text tokens against per-pool whitelist (e.g., {artifact_stage} → actual stage).
6. Return event object { id, text, pool, trigger }.
```

**`_select()` algorithm:**

```
1. Load events from content/events/{pool}.yml (already validated at startup).
2. Filter by trigger.
3. Filter by min_day / max_day.
4. Filter by conditions (all must pass).
5. Weighted random pick from remainder.
6. Return event definition hashref or undef if pool empty.
```

**Range resolution:**

```perl
sub _resolve_value ($self, $raw, $spec, $rng) {
    return $raw unless ref $raw eq 'ARRAY';
    die "range not allowed" unless grep { $_ eq 'range' } @{ $spec->{accepts} };
    my ($min, $max) = @$raw;
    die "range reversed" if $min > $max;
    die "bounds exceeded" unless $self->_in_bounds($min, $spec) && $self->_in_bounds($max, $spec);
    my $r = $rng ? $rng->() : rand();
    return $min + int($r * ($max - $min + 1));
}
```

### 1.2 Add `add_scrap` / `add_score` to Character Model

**File**: `lib/MagicMountain/Model/Character.pm`

Effect handlers call `$char->add_scrap($n)` and `$char->add_score($n)`.
These methods don't exist yet. Add them:

```perl
sub add_scrap ($self, $n) {
    my $scrap = $self->getCol('scrap') + $n;
    $scrap = 0 if $scrap < 0;   # invariant: scrap >= 0
    $self->setCol('scrap', $scrap);
}

sub add_score ($self, $n) {
    my $score = $self->getCol('score') + $n;
    $self->setCol('score', $score);   # invariant: score never decreases
}
```

The existing `validate` method already enforces scrap >= 0 and score
never-decreases — these methods complement that by clamping before write.

### 1.3 Register Prospecting Conditions

In `conditions->{prospecting}`:

```perl
artifact_stage => {
    label      => 'Artifact stage is',
    value_type => 'string',
    accepts    => ['scalar'],
    values     => ['stable', 'strained', 'unstable'],
    handler    => sub ($ctx, $val) { ($ctx->{artifact}{stage} // '') eq $val },
},
scrap_gte => {
    label      => 'Scrap >= N',
    value_type => 'integer',
    accepts    => ['scalar'],
    bounds     => [0, 9999],
    handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('scrap') // 0) >= $n },
},
scrap_lte => {
    label      => 'Scrap <= N',
    value_type => 'integer',
    accepts    => ['scalar'],
    bounds     => [0, 9999],
    handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('scrap') // 0) <= $n },
},
score_lte => {
    label      => 'Score <= N',
    value_type => 'integer',
    accepts    => ['scalar'],
    bounds     => [0, 99999],
    handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('score') // 0) <= $n },
},
prospecting_gte => {
    label      => 'Prospecting >= N',
    value_type => 'integer',
    accepts    => ['scalar'],
    bounds     => [0, 4],
    handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_prospecting') // 0) >= $n },
},
# ... upcycling_gte, selling_gte (same pattern)
```

### 1.4 Register Prospecting Effects

In `effects->{prospecting}`:

```perl
scrap_delta => {
    label      => 'Adjust scrap',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [-100, 500],
    handler    => sub ($ctx, $n) { $ctx->{char}->add_scrap($n) },
},
score_delta => {
    label      => 'Adjust score',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [0, 25],
    pools      => ['prospecting'],   # enforced at load time
    handler    => sub ($ctx, $n) { $ctx->{char}->add_score($n) },
},
value_delta => {
    label      => 'Adjust artifact value',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [-10, 50],
    handler    => sub ($ctx, $n) { $ctx->{artifact}{value} += $n },
},
instability_delta => {
    label      => 'Adjust artifact instability',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [-5, 10],
    handler    => sub ($ctx, $n) { $ctx->{artifact}{instability} += $n },
},
behavior_add => {
    label      => 'Add behavior tag',
    value_type => 'string',
    accepts    => ['scalar'],
    handler    => sub ($ctx, $tag) { push @{ $ctx->{artifact}{behaviors} }, $tag },
},
ap_delta => {
    label      => 'Adjust AP',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [-3, 1],
    handler    => sub ($ctx, $n) {
        my $ap = $ctx->{char}->getCol('action_points') + $n;
        $ap = 0 if $ap < 0;
        $ctx->{char}->setCol('action_points', $ap);
    },
},
```

**Note on handler style**: Handlers call domain methods on the character model
(`add_scrap`, `add_score`) rather than `setCol`/`getCol` directly. If the
SeasonalCharacter wrapper or a domain API doesn't yet expose these methods,
add them as part of this phase. The handlers are the right pressure to
improve the model.

### 1.5 YAML Loading + Validation

**Prerequisite**: Create the directory: `mkdir -p content/events`.

**File**: `content/events/prospecting.yml`

Populate with the passive events from the proposal (`loose_scrap_cache`,
`seismic_echo`, `unstable_pocket`, `secondary_signal`, `mountain_exhales`,
`late_break`).

`load($pool)` reads the file, runs every validation listed in proposal §6
(Validation at Load Time), caches the result, returns the validated arrayref.
Called at startup from `MagicMountain.pm`:

```perl
$self->random_events->load('prospecting');
$self->random_events->load('market_visit');
$self->random_events->load('global');
```

### 1.6 Integrate into `Prospecting::begin`

In `lib/MagicMountain/Activity/Prospecting.pm`, at the end of the `begin`
handler, after `_apply_defaults` and before `save`:

```perl
my $event = $self->app->random_events->draw(
    pool    => 'prospecting',
    trigger => 'begin',
    context => {
        artifact => $artifact,
        char     => $char,
        season   => $season,
    },
);

my $event_view;
if ($event) {
    $event_view = { id => $event->{id}, text => $event->{text} };
}
```

Include `$event_view` in the returned view hashref alongside `result`,
`artifact`, and `player`.

### 1.7 View + Template

The `view` hashref returned by `begin` now has an optional `event` key:

```perl
{ ok => 1, result => 'start', artifact => { ... }, player => { ... },
  event => { id => 'seismic_echo', text => 'SENSORY ALERT — ...' } }
```

**Template**: `templates/prospecting/actions.html.ep` — if `$event` is
present, render `$event->{text}` in a PB3K advisory style (small text,
amber `WARNING`/`ALERT`/`NOTICE` prefix). Existing outcome text renders
normally above it.

**Example CSS**: `#advisory-event` or a reusable class for event text blocks.

### 1.8 Tests

**File**: `t/service_random_events.t`

- loads YAML, validates structure, rejects bad fields
- condition evaluation (artifact_stage, scrap_gte, score_lte, skill gates)
- effect application (scrap_delta, value_delta, instability_delta, behavior_add, ap_delta)
- range resolution with seeded RNG
- event_chance rolling (inject sub that returns 0 → undef, returns 0.01 → event fires)
- weighted selection (set event_chance to 1.0, set up pool with known events, verify distribution)
- unknown condition/effect name dies
- range in condition dies
- out-of-bounds value dies
- duplicate event ID dies
- condition value with wrong type dies (string for scrap_gte)
- `weight: 0` or negative rejected
- empty trigger pool returns undef (no crash when no events match)
- text tokens validated against per-pool whitelist
- unknown text token dies

**File**: `t/prospecting_events.t`

- Integration: `begin` with srand, verify event fires and artifact/char mutated
- `begin` with srand that avoids event_chance roll, verify no event fires
- View includes event text when event fires
- View omits event key when no event fires
- `late_break` event fires only when score <= threshold
- `late_break` event does not fire when score > threshold
- `scrap_delta` with negative value clamped to non-negative (model invariant)
- `ap_delta` exceeding action_points_max (clamped by model)
- `behavior_add` with duplicate tag (no-op, artifact already has it)
- `value_delta` producing negative artifact value → value stays >= 0
- `min_day` and `max_day` boundaries (off-by-one for day == min_day, day == max_day)

**File**: `t/prospecting_web.t` (add subtests)

- Fragment contains event advisory text when event fires
- Fragment does not contain event advisory when no event fires

### 1.9 Phase 1 Completion Criteria

- Passive events fire during `Prospecting::begin` at configured probability
- All 6 prospecting passive events work end-to-end
- Event text appears in view and HTML
- All validation rules enforced at startup
- Tests pass with `prove -l t/service_random_events.t t/prospecting_events.t`
- `make indent && make clean` passes
- `make cover && make report` — coverage at or above 85%
- `bin/walkthrough` updated to show event text in prospecting flow

---

## Phase 2: Choice Events (Prospecting)

**Goal**: Choice events fire during `Prospecting::begin`. The player sees
choice buttons, picks one, and effects are applied. Bots auto-resolve.

### 2.1 Extend `draw()` for Choice Events

In `Service::RandomEvents::_select()`:

After condition filtering, for events with `choices`:
- Evaluate each choice's `conditions`
- Discard choices that fail any condition
- Discard event if no choices remain

`draw()` returns the event object with `choices` populated (snapshot of
resolved effects per choice) and `effects` empty.

Add `has_choices` convenience method on the event object.

Add `apply_choice($pool, $choice_id, $context, $pending_event)` method that runs the chosen
effects through the handler registry.

### 2.2 Store Pending Event on Activity Row

**Prerequisite**: Add `pending_event` to the Activity base class `columns`
in `lib/MagicMountain/Activity.pm:16`. Without this, `setCol('pending_event', ...)`
dies with "no such column."

When `$event->{has_choices}`, the `begin` handler:

1. Does NOT call `$event->apply()`
2. Stores the event snapshot as `pending_event` on the activity row:

```perl
$self->setCol('pending_event', {
    pool     => 'prospecting',
    event_id => $event->{id},
    day      => $season->{day},
    choices  => $event->{choices},   # already filtered, ready to render
});
$self->save;
```

3. Returns view with `result => 'event'` and choices array (see below)

### 2.3 Add `resolve_event` to Prospecting Activity

**File**: `lib/MagicMountain/Activity/Prospecting.pm`

Add to transition table:

```perl
has transitions => sub {
    {
        idle           => ['begin'],
        processing     => ['push', 'stop', 'resolve_event'],
    }
};
```

Add `resolve_event` handler:

```perl
sub resolve_event ($self, $char, %params) {
    my $choice_id = $params{choice_id} or die "missing choice_id";

    my $pending = $self->getCol('pending_event')
        or die "no pending event";

    die "expired" if $pending->{day} != $self->app->active_season->{day};

    my ($choice) = grep { $_->{id} eq $choice_id } @{ $pending->{choices} }
        or die "unknown choice '$choice_id'";

    # Apply chosen effects through the Service's public API.
    # The Service already has apply_choice — use it, don't reach into
    # the effects registry directly.
    $self->app->random_events->apply_choice(
        pool      => 'prospecting',
        choice_id => $choice_id,
        context   => {
            artifact => $self->artifact,    # artifact still on activity row from begin
            char     => $char,
            season   => $self->app->active_season,
        },
        pending_event => $pending,          # snapshot stored on activity
    );

    $self->setCol('pending_event', undef);
    $self->save;
    $char->save;

    return {
        view => {
            ok       => 1,
            result   => 'start',
            artifact => $self->_artifact_view($self->artifact),
            player   => $self->_player_snapshot($char),
        },
    };
}
```

### 2.4 View Contract

When a choice event fires, the view replaces the normal outcome:

```perl
{
    view => {
        ok     => 1,
        result => 'event',
        event  => {
            id      => 'sealed_battery_case',
            text    => 'A sealed field case hums weakly...',
            choices => [
                {
                    id         => 'strip',
                    label      => 'Strip it for parts',
                    action_url => '/prospecting/resolve_event',
                    params     => { choice_id => 'strip' },
                },
                # ... more choices
            ],
        },
    },
}
```

Each choice is rendered as a button following the standard `action_buttons`
component contract (label, action_url, method=POST, params).

### 2.5 Controller

**File**: `lib/MagicMountain/Controller/Prospecting.pm`

Add `resolve_event` action that dispatches through the activity. Follows
the existing controller pattern (no business logic in controller).

**Route**: In `MagicMountain.pm:buildRoutes`, add after the existing
prospecting write routes:

```perl
$auth_write->post('/prospecting/resolve_event')->to('prospecting#resolve_event');
```

### 2.6 Bot Handling

**Deferred**: A bot orchestration loop (prospect → push → stop → sell)
does not yet exist in the codebase. `Bot::PushPolicy` is a pure policy
evaluator, not a runtime loop. When bot automation is built,
choice-event auto-resolution follows this pattern:

```perl
if ($result->{view}{result} eq 'event') {
    my $choice_id = $result->{view}{event}{choices}[0]{id};
    $activity->dispatch($char, 'resolve_event', choice_id => $choice_id);
    # continue normal flow
}
```

Bots always pick the first eligible choice. Content policy: make the first
choice safe/reasonable (see authoring guide).

### 2.7 Simulation Compatibility

**File**: `lib/MagicMountain/Command/simulate.pm`

The simulation calls `$activity->dispatch($char, 'begin')` at line 255.
After Phase 2, choice events will return `result: 'event'` instead of
`result: 'start'`. Update the simulation prospecting loop (around line
255-270) to handle this:

```perl
my $result = $activity->dispatch($char, 'begin');

# Handle choice events: auto-resolve first eligible choice
if ($result->{view}{result} eq 'event') {
    my $choice_id = $result->{view}{event}{choices}[0]{id};
    $result = $activity->dispatch($char, 'resolve_event', choice_id => $choice_id);
}

# Continue existing push loop — expects result: 'start'
my $push_policy = ...;  # unchanged
while ($push_policy->should_push(...)) {
    my $r = $activity->dispatch($char, 'push');
    ...
}
```

Passive events require no changes — they apply inside `begin` and the
simulation ignores the extra `event` key in the view.

### 2.8 Populate Choice Events in YAML

Add `sealed_battery_case` and `abandoned_cache` to
`content/events/prospecting.yml`.

### 2.9 Tests

**File**: `t/service_random_events.t` (add subtests)

- choice event returned with choices populated and effects empty
- choice conditions filter out ineligible choices
- event discarded when all choices gated out
- apply_choice runs correct effects
- apply_choice with bad choice_id dies

**File**: `t/prospecting_events.t` (add subtests)

- `begin` returns `result: 'event'` with choice buttons
- player selects choice, effects applied
- ungated choice hidden from player without skill
- `resolve_event` rejects expired (wrong day) pending event
- `resolve_event` dies with "no pending event" if called without one
- `resolve_event` dies with "unknown choice" for bad choice_id

**File**: `t/prospecting_web.t` (add subtests)

- `/prospecting/resolve_event` returns 200 with choice
- `/prospecting/resolve_event` returns 400 without pending event

### 2.10 Phase 2 Completion Criteria

- Choice events fire, present buttons, resolve correctly
- Skill-gated choices hidden from unqualified players
- Bot auto-resolution works
- Pending events expire at day rollover
- All tests pass
- `make indent && make clean` passes
- `make cover && make report` — coverage at or above 85%

---

## Phase 3: Market Visit Events

**Goal**: Passive events fire at the start of a market visit. Customer state
is mutated before negotiation begins. No choice events for market in v1.

### 3.1 Register Market Conditions + Effects

In `Service::RandomEvents`:

**Conditions**: `faction_days_no_buy_gte`, `standing_gte`, `scrap_gte`,
`sold_gte`, `selling_gte`.

**Effects**: `multiplier_delta`, `irritation_floor`, `faction_delta`.

The market context includes `customer`, `char`, `standing`, `faction_state`,
and `season`. Effect handlers mutate `customer` in-place (e.g., add to
`_multiplier_delta` ephemeral field that the MarketVisit activity reads
after event processing and bakes into the real multiplier calculation).

### 3.2 Create `content/events/market_visit.yml`

Populate with the market events from the proposal: `desperate_courier`,
`flooded_market`, `thin_skinned`, `faction_bounty`.

### 3.3 Integrate into `MarketVisit::begin`

In `lib/MagicMountain/Activity/MarketVisit.pm`, at the end of the `begin`
handler, after customer generation and before save:

```perl
my $event = $self->app->random_events->draw(
    pool    => 'market_visit',
    trigger => 'begin',
    context => {
        customer      => $customer,
        char          => $char,
        standing      => \%standing,
        faction_state => \%faction_state,
        season        => $season,
    },
);

if ($event) {
    # ephemeral fields like _multiplier_delta are on the customer hash
    # The rest of the begin handler reads them before computing offer prices
    $event_view = { id => $event->{id}, text => $event->{text} };
}
```

MarketVisit's `begin` handler reads ephemeral `_multiplier_delta` after
event processing and applies it to the dynamic multiplier calculation.

### 3.4 View + Template

Same pattern as Prospecting — `event` key in view, advisory styling in
the market visit fragment template.

### 3.5 Tests

**File**: `t/market_visit_events.t`

- Events fire during `begin`
- `desperate_courier` fires only when faction hasn't bought in >= 3 days
- `multiplier_delta` adjusts the effective multiplier
- `irritation_floor` sets minimum irritation
- `faction_delta` adjusts standing
- Event text in view when event fires

### 3.6 Phase 3 Completion Criteria

- Market events fire at `begin` with correct conditions
- Customer state mutated correctly
- Event text appears in market view

---

## Phase 4: Global Events + Crier

**Goal**: Once per day, a global event may fire, setting daily modifiers that
affect all characters. The Crier narrates global events directly and detects
aggregate personal event patterns.

### 4.1 Season Model Changes

**File**: `lib/MagicMountain/Model/Season.pm`

Add three columns to the `columns` declaration in `Season.pm` (around line 5-8):

```perl
columns => [qw(
    day length status created_at updated_at
    crier_message crier_snapshot leaderboard_snapshot archived_at
    daily_modifiers personal_event_counts global_event_text
)]
```

- `daily_modifiers` — JSON hashref, default `{}`. Written by global events,
  cleared each maintenance before new event is drawn.
- `personal_event_counts` — JSON hashref, per-day aggregate counts.
  Accumulated by activity callers after personal event draws.
- `global_event_text` — string, null. Set by maintenance when a global
  event fires. Read by Crier::generate() verbatim for the day's message.
  Cleared alongside daily_modifiers.

Note: `global_event_text` is on the Season model, NOT as Crier state.
Crier::generate() reads it from `$season->getCol('global_event_text')`
— the Crier remains stateless.

**Domain API** (method on Season model, not raw hash access):

```perl
sub daily_modifier ($self, $key, $default) {
    my $mods = $self->getCol('daily_modifiers') // {};
    return exists $mods->{$key} ? $mods->{$key} : $default;
}

sub prospect_ap_cost ($self) {
    return $self->daily_modifier('prospect_ap_cost', 2);
}
```

### 4.2 Register Global Effects

In `effects->{global}`:

```perl
collapse_chance_mult => { ... writes daily_modifiers.collapse_chance_mult },
instability_growth_delta => { ... writes daily_modifiers.instability_growth_delta },
artifact_value_mult => { ... writes daily_modifiers.artifact_value_mult },
prospect_ap_cost => { ... writes daily_modifiers.prospect_ap_cost, bounds [1,3] },
market_multiplier_delta => { ... writes daily_modifiers.market_multiplier_delta },
```

Each handler receives `($ctx, $n)` and does:

```perl
$ctx->{season}->setCol('daily_modifiers', {
    %{ $ctx->{season}->getCol('daily_modifiers') // {} },
    collapse_chance_mult => $n,
});
```

### 4.3 Register Global Conditions

In `conditions->{global}`:

```perl
any_faction_days_no_buy_gte => {
    label      => 'Any faction days without purchase >= N',
    value_type => 'integer',
    accepts    => ['scalar'],
    bounds     => [0, 99],
    handler    => sub ($ctx, $n) {
        for my $fid (keys %{ $ctx->{faction_state} }) {
            return 1 if ($ctx->{faction_state}{$fid}{days_since_purchase} // 0) >= $n;
        }
        return 0;
    },
},
```

### 4.4 Create `content/events/global.yml`

Populate with `mountain_unrest`, `rich_veins`, `mountain_slumber`,
`buyer_market`, `faction_crackdown`.

### 4.5 Maintenance Integration

**File**: `lib/MagicMountain.pm` — the existing `on_maintenance` callback
(around lines 137-197) already handles day advancement, AP reset, shed
decay, Crier generation, faction snapshots, market dynamics reset, and
bot runs. **Insert** the global event step into this existing flow — do
not rewrite it.

```perl
# EXISTING: season day check, catch-up loop, etc.

# INSERT before day advancement (before $season->setCol('day', $day)):
$season->setCol('daily_modifiers', {});                  # clear yesterday's modifiers
$season->setCol('global_event_text', undef);

# EXISTING: advance day, reset AP (already handles AP = action_points_max)

# INSERT after market dynamics reset (after day_appetite reset, around line 176),
# but before Crier generation (around line 157):
my $event = $self->app->random_events->draw(
    pool    => 'global',
    trigger => 'day_start',
    context => {
        season        => $season,
        faction_state => \%faction_state,
    },
);

if ($event) {
    $event->apply({
        season        => $season,
        faction_state => \%faction_state,
    });
    $season->setCol('global_event_text', $event->{text});
    $season->save;
}

# EXISTING: Crier generation. Crier::generate() now reads
# $season->getCol('global_event_text') first. If present, uses it
# verbatim. Otherwise falls back to faction-state diffing.

# EXISTING: write faction snapshots, crier snapshot, bot day actions
```

### 4.6 Read Modifiers in Activities

**In `Prospecting::begin`** — read `prospect_ap_cost` and `artifact_value_mult`:

The existing `begin` handler hardcodes AP cost to 2 (line 181: `die "AP exhausted" unless AP >= 2`,
line 190: `setCol('action_points', ... - 2)`). Both references must use the
variable cost:

```perl
my $ap_cost = $season->prospect_ap_cost;  # daily_modifiers value or default 2
die "AP exhausted" unless ($char->getCol('action_points') // 0) >= $ap_cost;
# ...
$char->setCol('action_points', $char->getCol('action_points') - $ap_cost);
my $value_mult = $season->daily_modifier('artifact_value_mult', 1);
# multiply into artifact->{value} or base_value as appropriate
```

**In `Prospecting::push`** — read `collapse_chance_mult` and
`instability_growth_delta`:

```perl
my $collapse_mult = $season->daily_modifier('collapse_chance_mult', 1);
my $collapse_chance = ($ratio ** 3) * 0.80 * $collapse_mult;
$growth += $season->daily_modifier('instability_growth_delta', 0);
```

**In `MarketVisit`** — read `market_multiplier_delta`:

Add to the dynamic multiplier calculation:
```perl
$effective_mult += $season->daily_modifier('market_multiplier_delta', 0);
```

### 4.7 Crier Changes

**File**: `lib/MagicMountain/Crier.pm`

**Global event narration**: `generate()` reads `$season->getCol('global_event_text')`.
If present, uses it verbatim as the day's message. If absent, falls back to
normal faction-state diffing. The Crier remains **stateless** — the Season
model carries the event text alongside `crier_message`.

**Aggregate pattern detection**: After reading `personal_event_counts` from
the Season model, check for surge/downturn patterns (same event >= 5 times,
rate change >= 50%). If a pattern matches AND no global event fired, select
from `events.surge` or `events.downturn` crier message templates.

Add `events` message category to `content/flavor/crier.yml`:

```yaml
crier_messages:
  events:
    surge:
      - "SEISMIC READINGS elevated across the basin..."
      - "The mountain is restless today..."
    downturn:
      - "Market activity quiet. Buyers maintaining position..."
```

### 4.8 Personal Event Count Logging

The Service does NOT call persistence directly. After `draw()` returns an
event, the **caller** (activity handler or maintenance callback) logs the
count to the Season model:

```perl
# In activity handler or maintenance callback, after draw() succeeds:
my $counts = $season->getCol('personal_event_counts') // {};
$counts->{$pool}{$event->{id}}{fired}++;
$season->setCol('personal_event_counts', $counts);
$season->save;
```

For choice events, the caller increments `resolved` after `apply_choice`
succeeds.

This keeps the Service read-only (no persistence calls). The Season
model's `save` is the caller's responsibility.

### 4.9 Tests

**File**: `t/global_events.t`

- Maintenance draws global event, modifiers written to season
- Activities read modifiers correctly (prospect_ap_cost, collapse_chance_mult, etc.)
- `prospect_ap_cost: 1` → prospecting costs 1 AP
- `collapse_chance_mult: 1.5` → collapse 50% more likely
- `artifact_value_mult: 1.2` → artifact base value 20% higher
- `any_faction_days_no_buy_gte` condition works
- Day without global event: modifiers empty, defaults used
- Yesterday's modifiers cleared before today's drawn

**File**: `t/crier_events.t`

- Global event text used as Crier message
- Pattern detection: >= 5 of same personal event triggers surge message
- Pattern detection: rate change triggers surge/downturn
- No patterns, no global event → Crier falls back to faction diff

### 4.10 Phase 4 Completion Criteria

- Global events fire at most once per day during maintenance
- Daily modifiers are read by Activities and affect gameplay
- Season::daily_modifier() API used everywhere (no raw hash access)
- Crier narrates global events directly
- Crier detects personal event patterns in aggregate
- All tests pass
- `make indent && make clean` passes
- `make cover && make report` — coverage at or above 85%

---

## Phase 5: Content Population + Docs

**Goal**: All pools populated with v1 events. Authoring guide written.
Walkthrough updated.

### 5.1 Populate YAML Files

All three files populated with the events from the proposal:
- `content/events/prospecting.yml` — 6 passive + 2 choice events
- `content/events/market_visit.yml` — 4 passive events
- `content/events/global.yml` — 5 global events

Each event verified: valid IDs, weights positive integers, triggers correct,
conditions use registered predicates, effects use registered handlers,
text tokens from whitelist only.

### 5.2 Write Authoring Guide

**File**: `docs/how-to-write-events.md`

- Mini-language reference (the cheat sheet)
- Choosing weight values relative to pool peers
- Day gate pacing strategy
- PB3K text style conventions
- When to use passive vs choice events
- Skill gate philosophy
- Catch-up event design with `score_lte`
- Bot-first-choice safety
- How to test locally with `MM_RAND_SEED`
- Validation: what `start.sh` checks before it boots

### 5.3 Update Walkthrough

`bin/walkthrough` must handle the event flow:

**Passive events**: After `begin`, check the JSON response for an `event`
key. If present, log the event text. If absent, continue normally. Use
`MM_RAND_SEED` to control whether events fire during walkthrough runs.

**Choice events**: After `begin`, check for `result: 'event'` in the JSON
response. If present:
1. Extract `$result->{event}{choices}` array
2. Read `action_url` and `params` from the first eligible choice
3. POST to `action_url` with `params` as JSON body
4. Verify the response returns `result: 'start'` (normal flow resumes)

The walkthrough's prospecting scene (`§4`, lines 222-244) must add these
checks after each `begin` call. The walkthrough should work with both
`MM_RAND_SEED=0` (no events, baseline path) and with seeds that trigger
events.

### 5.4 Smoke Tests

```bash
bash bin/smoke_test_endpoint GET /prospecting/begin?_format=fragment
bash bin/smoke_test_endpoint POST /prospecting/resolve_event
```

### 5.5 Phase 5 Completion Criteria

- All YAML files pass load-time validation
- Walkthrough exercises event flow (passive + choice)
- Authoring guide is clear enough for a new contributor
- Full test suite passes: `prove -l t/`
- Coverage stays at or above 85%
- `make indent && make clean` passes
