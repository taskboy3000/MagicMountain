# Magic Mountain — Random Events v2

*A lightweight, YAML-driven random event system. Three event pools — personal
(per-character during activity begin), global (at most one per day, affects all
characters), and market (per-character during negotiation begin). Designed as
a Service consumed by existing Activities and the maintenance callback — no
new model classes, no event engine, no persistent buff system.*

---

## 1. Design Goals

1. **Personal and global events** — Personal events fire per-character at the
   start of an activity (prospecting begin, market visit begin). Global events
   fire at most once per day during maintenance and write daily modifiers to
   the Season row — affecting all characters for that day's play.

2. **Transient effects only** — No persistent modifiers, no buff timers, no
   new character columns. Personal events are baked into state the Activity
   already persists. Global events live in `$season->{daily_modifiers}` and
   are cleared at the next maintenance.

3. **YAML as data, Perl as logic** — YAML contains named references to
   registered handlers — never executable code. Adding an event is a content
   edit; adding a new kind of condition or effect requires one Perl sub in
   the dispatch table.

4. **One file per event pool** — `content/events/prospecting.yml`,
   `content/events/market_visit.yml`, and `content/events/global.yml`. One
   file = one pool = one context shape.

5. **Passive and choice-based events** — Most personal events fire alongside
   an action and apply their effects immediately. Some present the player with
   choices, delaying effect application. Choice options use the same
   `conditions` mechanism for any gating. Global events are always passive.

6. **Minimal infrastructure** — No event engine, no new model classes. A
   single Service class (`Service::RandomEvents`) plus one new action per
   Activity (`resolve_event`) for player choices. Global events write a
   `daily_modifiers` hashref on the existing Season model — read through
   a narrow domain API, not raw hash access.

7. **PB3K framing** — Events appear as device sensor readings, system
   advisories, or environmental readings — never as game-UI "notifications."

8. **World feedback loop** — Personal events are recorded to a daily log; the
   Crier detects aggregate patterns. Global events are narrated directly by
   the Crier as the day's "weather report."

9. **Bot-transparent** — Bots encounter personal events via the same
   `dispatch()` path (auto-selecting the first eligible choice). Global event
   modifiers affect bots automatically — they read `$season->{daily_modifiers}`
   like everyone else.

---

## 2. Mini-Language Philosophy

The YAML contains exactly one kind of expression: `{ name: value }` — a
single-key map where the key is a registered handler name. Conditions
always use scalar values (deterministic predicates). Effects may use scalars
or two-element range arrays `[min, max]`.

There is no grammar beyond this. No operators, no nesting, no string
expressions, no boolean composition (OR, NOT). New capability is added by
registering a new handler name in the Perl dispatch table — the YAML does
not grow syntax.

| What you write | What it means |
|---------------|---------------|
| `scrap_delta: 25` | Add exactly 25 scrap |
| `scrap_delta: [5, 25]` | Add a random amount between 5 and 25 scrap |
| `scrap_delta: -10` | Remove 10 scrap |
| `prospecting_gte: 2` | Character has prospecting skill >= 2 |

### Text Tokens

Event `text` may contain registered placeholders. These are validated at
load time — unknown tokens die. The registered set per pool:

| Pool | Allowed Tokens |
|------|---------------|
| `prospecting` | `{artifact_stage}`, `{artifact_signal}` |
| `market_visit` | `{faction_name}`, `{buyer_name}` |
| `global` | *(none — text is used verbatim)* |

No expressions, no nested properties, no method calls. `{faction_name}`
is resolved by the Service; `{customer.faction.name}` is rejected.

---

## 3. V1 Scope

- Personal events fire only at `trigger: begin` — the start of prospecting
  or the start of a market visit. No push-phase or offer-phase events in v1.
  If mid-activity events prove useful later, adding a `push` or `offer`
  trigger is a single-line registry change.
- Choice events fire only at `trigger: begin` for prospecting. Pausing
  in the middle of market negotiation is deferred until the pattern is
  proven.
- Global events fire at `trigger: day_start` during maintenance.

---

## 4. Event Types

### Passive Events

Fire alongside an action. Effects are applied immediately. The player sees
flavor text in the view alongside the normal action outcome.

```yaml
- id: loose_scrap_cache
  weight: 8
  trigger: begin
  min_day: 2
  conditions:
    - artifact_stage: stable
  text: >
    Your boot knocks loose a panel that was never meant to be found.
    Behind it: wire, foil, chipped ceramic, and a few useful parts.
  effects:
    - scrap_delta: [5, 25]
```

### Choice Events

Fire alongside an action but effects are NOT applied immediately. The player
is presented with a choice. Each choice is a self-contained mini-event with
its own `id`, `label`, optional `conditions`, and `effects`.

```yaml
- id: sealed_battery_case
  weight: 5
  trigger: begin
  min_day: 3
  text: >
    A sealed field case hums weakly under a layer of grit.
    The warning label is sun-bleached except for the word SERVICE.
  choices:
    - id: strip
      label: Strip it for parts
      effects:
        - scrap_delta: [10, 30]

    - id: preserve
      label: Preserve the casing
      effects:
        - scrap_delta: 5
        - ap_delta: 1

    - id: force_open
      label: Force it open
      conditions:
        - prospecting_gte: 2
      effects:
        - scrap_delta: [0, 60]
        - instability_delta: 2
```

Choices use the same `conditions` mechanism as events. No special
`skill_min`/`skill_max` fields — skill gates are conditions.

If all choices are gated out (e.g., every choice has an unmet condition),
the event does not fire. The choice event object returned by the Service
has `choices` populated and `effects` empty.

### Global Events

Fire **at most once per day** during maintenance (`on_maintenance`
callback). The maintenance order is explicit because modifiers interact
with AP reset, market state, bots, and human play:

```
1. Clear yesterday's daily_modifiers from the Season row
2. Advance season day
3. Reset all characters' AP
4. Reset market dynamics (daily_intake = 0, days_since_purchase++)
5. Draw today's global event (roll global_event_chance → weighted pick)
6. Apply global event to $season->{daily_modifiers}
7. Write Crier message (global event text or faction-diff fallback)
8. Run bot day actions
```

This ensures modifiers are active for the full day and visible to every
character — player or bot — that acts after maintenance.

The maintenance callback first rolls against a configurable base chance
(`global_event_chance`, e.g. 0.60 = 60% of days have a global event). If
the roll succeeds, one event is drawn from the global pool via weighted
random selection. If the roll fails, no global event fires that day.

Effects write to `$season->{daily_modifiers}`, a hashref that Activities
consult during the day. Modifiers are cleared at the next maintenance.

```yaml
# content/events/global.yml

- id: mountain_unrest
  weight: 6
  trigger: day_start
  min_day: 5
  text: "SEISMIC ADVISORY — Elevated resonance across the basin. All artifact containment rated at reduced stability."
  effects:
    - collapse_chance_mult: 1.25

- id: rich_veins
  weight: 4
  trigger: day_start
  min_day: 3
  text: "GEOSURVEY UPDATE — Substrate density readings suggest high-value pockets near surface. Priority extraction recommended."
  effects:
    - artifact_value_mult: 1.15

- id: mountain_slumber
  weight: 5
  trigger: day_start
  text: "STABILITY REPORT — Seismic activity at seasonal low. Extended extraction windows available."
  effects:
    - prospect_ap_cost: 1

- id: buyer_market
  weight: 5
  trigger: day_start
  min_day: 10
  text: "FACTION BULLETIN — Multiple buyers reporting supply shortages. Procurement budgets expanded."
  effects:
    - market_multiplier_delta: 0.10

- id: faction_crackdown
  weight: 3
  trigger: day_start
  min_day: 15
  text: "ENFORCEMENT NOTICE — Faction compliance patrols active in the bazaar. Standings under review."
  conditions:
    - any_faction_days_no_buy_gte: 4
  effects:
    - collapse_chance_mult: 1.15
    - market_multiplier_delta: -0.05
```

---

## 5. YAML Structure

### File Organization

```
content/events/prospecting.yml    # Pool: prospecting
content/events/market_visit.yml   # Pool: market_visit
content/events/global.yml         # Pool: global
```

One file per pool. No cross-pool references. The file name IS the pool name.

### Top-Level Key

Each file contains a single top-level list — no wrapping key:

```yaml
# content/events/prospecting.yml
- id: loose_scrap_cache
  weight: 8
  ...

- id: sealed_battery_case
  weight: 5
  ...
```

### Field Reference

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `id` | yes | — | Unique identifier within the pool |
| `weight` | yes | — | Relative probability among eligible events |
| `trigger` | yes | — | `begin` (personal) or `day_start` (global) |
| `min_day` | no | null | Only fire on or after this season day |
| `max_day` | no | null | Only fire on or before this season day |
| `conditions` | no | `[]` | Array of `{ predicate: arg }` maps — all must pass (AND); scalars only, never ranges |
| `effects` | passive events: yes; choice events: no | — | Array of `{ handler: arg }` maps — applied in order |
| `choices` | choice events: yes; passive events: no | — | Array of choice objects |
| `text` | yes | — | Player-facing flavor text with optional registered tokens |

### Choice Object Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `id` | yes | — | Unique within this event, used as the `choice_id` param |
| `label` | yes | — | Short button text shown to the player |
| `conditions` | no | `[]` | Same mechanism as event-level conditions — choice hidden if any fails |
| `effects` | yes | — | Array of `{ handler: arg }` maps — applied when selected |

No special skill gate fields. Skill checks are conditions like any other.

### Full Example: Prospecting Events

```yaml
# content/events/prospecting.yml

# ── Passive events ─────────────────────────────────────────────────────

- id: loose_scrap_cache
  weight: 8
  trigger: begin
  min_day: 2
  text: >
    Your boot knocks loose a panel that was never meant to be found.
    Behind it: wire, foil, chipped ceramic, and a few useful parts.
  effects:
    - scrap_delta: [5, 25]

- id: seismic_echo
  weight: 8
  trigger: begin
  min_day: 3
  text: "SENSORY ALERT — Low-frequency resonance detected. Substrate analysis suggests a dense pocket nearby."
  effects:
    - value_delta: 4

- id: unstable_pocket
  weight: 5
  trigger: begin
  text: "STABILITY WARNING — Localized field distortion. Artifact containment may be compromised."
  effects:
    - instability_delta: 2

- id: secondary_signal
  weight: 4
  trigger: begin
  text: "ANOMALY DETECTED — Artifact appears to have a secondary behavioral signature."
  effects:
    - behavior_add: signal

- id: mountain_exhales
  weight: 2
  trigger: begin
  max_day: 15
  text: "GEOPHYSICAL EVENT — The mountain vents. A loose artifact surfaces nearby."
  effects:
    - ap_delta: 1

- id: late_break
  weight: 6
  trigger: begin
  min_day: 8
  conditions:
    - score_lte: 200
  text: >
    OPPORTUNITY ADVISORY — Anomalous signal cluster in an under-prospected
    zone. Faction intelligence suggests high-value extraction for operators
    with room to advance.
  effects:
    - scrap_delta: [10, 30]
    - score_delta: [5, 15]

# ── Catch-up events ────────────────────────────────────────────────────
#
# Events gated by `score_lte` create rubberbanding: trailing players get
# score bumps to stay in the race; leaders (> threshold) don't qualify.
# The threshold is a YAML value — tune per season length.
# ── Choice events ──────────────────────────────────────────────────────

- id: sealed_battery_case
  weight: 5
  trigger: begin
  min_day: 3
  text: >
    A sealed field case hums weakly under a layer of grit.
    The warning label is sun-bleached except for the word SERVICE.
  choices:
    - id: strip
      label: Strip it for parts
      effects:
        - scrap_delta: [10, 30]

    - id: preserve
      label: Preserve the casing
      effects:
        - scrap_delta: 5
        - ap_delta: 1

    - id: force_open
      label: Force it open
      conditions:
        - prospecting_gte: 2
      effects:
        - scrap_delta: [0, 60]
        - instability_delta: 2

- id: abandoned_cache
  weight: 4
  trigger: begin
  min_day: 8
  text: >
    A shallow excavation abandoned by a prior team. Tools, scrap,
    and a half-extracted artifact casing remain.
  choices:
    - id: salvage
      label: Salvage what's left
      effects:
        - scrap_delta: [15, 40]

    - id: finish_extraction
      label: Finish their work
      conditions:
        - prospecting_gte: 2
      effects:
        - value_delta: [5, 15]
        - instability_delta: [-3, 0]

    - id: report
      label: Report to faction
      conditions:
        - prospecting_gte: 3
      effects:
        - score_delta: [5, 15]
```

### Full Example: Market Visit Events

```yaml
# content/events/market_visit.yml

- id: desperate_courier
  weight: 8
  trigger: begin
  conditions:
    - faction_days_no_buy_gte: 3
  text: "INCOMING TRANSMISSION — {faction_name} courier dispatching priority procurement. Backlog rates in effect."
  effects:
    - multiplier_delta: 0.25

- id: flooded_market
  weight: 5
  trigger: begin
  text: "MARKET ANALYSIS — Elevated supply detected in local inventory. Buyer leverage increased."
  effects:
    - multiplier_delta: -0.15

- id: thin_skinned
  weight: 4
  trigger: begin
  text: "PSYCH PROFILE — Buyer flagged as irritable. Recommend measured approach."
  effects:
    - irritation_floor: 2

- id: faction_bounty
  weight: 5
  trigger: begin
  conditions:
    - standing_gte: 2
  text: "NOTICE — {faction_name} has posted a procurement bonus for repeat partners. Standing recognized."
  effects:
    - multiplier_delta: 0.15
```

---

## 6. Condition & Effect Registry

The Service owns dispatch tables per pool. Names are validated at load time
— unknown names die. Values are validated against per-handler type metadata.

### Value Conventions

**Conditions** — scalar only. Always deterministic.

```
standing_gte: 2
artifact_stage: stable
prospecting_gte: 2           # skill predicates use the same condition mechanism
```

**Effects** — scalar or range. Range resolved by Service before handler call.

```
scrap_delta: 25              — exact integer
scrap_delta: -10             — negative integer (signed delta)
scrap_delta: [5, 25]         — random integer in [min, max] inclusive
multiplier_delta: 0.25       — exact float
faction_delta:               — map value (exception for compound parameters)
    faction: syndicate
    amount: 3
```

Ranges are for effects only. Conditions never accept ranges.

### Registered Conditions

**Prospecting pool:**

| Name | Argument | Returns true when |
|------|----------|-------------------|
| `artifact_stage` | string | `artifact.stage` equals the argument (`stable`, `strained`, `unstable`) |
| `scrap_gte` | integer | Character scrap >= N |
| `scrap_lte` | integer | Character scrap <= N |
| `score_lte` | integer | Character score <= N |
| `prospecting_gte` | integer | Character prospecting skill >= N |
| `upcycling_gte` | integer | Character upcycling skill >= N |
| `selling_gte` | integer | Character selling skill >= N |

**Market visit pool:**

| Name | Argument | Returns true when |
|------|----------|-------------------|
| `faction_days_no_buy_gte` | integer | Current customer's faction hasn't purchased in >= N days |
| `standing_gte` | integer | Character's standing with current customer's faction >= N |
| `scrap_gte` | integer | Character scrap >= N |
| `selling_gte` | integer | Character selling skill >= N |

**Global pool:**

| Name | Argument | Returns true when |
|------|----------|-------------------|
| `any_faction_days_no_buy_gte` | integer | Any faction hasn't purchased in >= N days |
| `total_season_sales_gte` | integer | Total season sales across all characters >= N |

Conditions are pool-specific — a condition defined for one pool cannot be
referenced by another. The Service validates this at load time.

### Registered Effects

**Personal effects (prospecting and market visit pools):**

| Name | Value Type | Accepts | Bounds | Pool | Description |
|------|------------|---------|--------|------|-------------|
| `scrap_delta` | signed int | scalar, range | [-100, 500] | either | Adjust character scrap by N |
| `score_delta` | signed int | scalar, range | [0, 25] | prospecting | Adjust character score by N. Choice events only; rejected in passive events. Reserve for narrative choice resolutions. |
| `value_delta` | signed int | scalar, range | [-10, 50] | prospecting | Adjust artifact value by N |
| `instability_delta` | signed int | scalar, range | [-5, 10] | prospecting | Adjust artifact instability by N |
| `behavior_add` | string | scalar | behaviors list | prospecting | Append a behavior tag to the artifact |
| `ap_delta` | signed int | scalar, range | [-3, 1] | prospecting | Adjust character action_points by N. Max refund of 1 AP. |
| `multiplier_delta` | signed float | scalar | [-0.50, 0.50] | market_visit | Adjust customer's effective multiplier by N |
| `irritation_floor` | unsigned int | scalar | [0, 5] | market_visit | Set customer irritation to at least N |
| `faction_delta` | map | `{faction, amount}` | amount: [-5, 5] | market_visit | Adjust standing with named faction by amount |

Effects deferred to future triggers: `gain_delta` (push-phase),
`match_mult` (offer-phase), `standing_mult` (offer-phase, multiplier
ambiguity). They return when their trigger does.

**Multiplier composition (additive only for v1):**

```
effective_multiplier =
    base_customer_multiplier
    + personal_multiplier_delta
    + global_market_multiplier_delta
```

No multiplication chains. The three terms are additive. Multiplicative
effects may be added later if additive deltas prove insufficient.

**Global effects (global pool only):**

Each writes to `$season->{daily_modifiers}->{$key}`, read by Activities
during the day:

| Name | Value Type | Bounds | Writes key | Description |
|------|------------|--------|------------|-------------|
| `collapse_chance_mult` | float | [0.5, 2.0] | `collapse_chance_mult` | Multiply collapse chance for all characters today |
| `instability_growth_delta` | signed int | [-2, 5] | `instability_growth_delta` | Add to instability growth per push for all characters |
| `artifact_value_mult` | float | [0.5, 2.0] | `artifact_value_mult` | Multiply artifact base value at draw time |
| `prospect_ap_cost` | unsigned int | [1, 3] | `prospect_ap_cost` | Override AP cost for prospecting begin (default 2). Never zero — at least 1 AP per action. |
| `market_multiplier_delta` | float | [-0.30, 0.30] | `market_multiplier_delta` | Adjust all faction multipliers today |

Activities read modifiers through a Season domain API, never the raw hash:

```perl
my $mult = $self->app->season->daily_modifier('artifact_value_mult', 1);
my $cost = $self->app->season->prospect_ap_cost;   # daily_modifier value or default 2
```

Absent keys return the caller's default — a day without a global event
plays identically to today's code. Global effects are always scalar in
v1 — no ranges.

### Registry Structure

Each entry carries enough metadata that the loader validates values at
startup without invoking the handler:

```perl
scrap_delta => {
    label      => 'Adjust scrap',
    value_type => 'integer',
    accepts    => ['scalar', 'range'],
    bounds     => [-100, 500],
    handler    => sub ($ctx, $n) { ... },
},

prospecting_gte => {
    label      => 'Prospecting >= N',
    value_type => 'integer',
    accepts    => ['scalar'],         # conditions: scalar only
    bounds     => [0, 4],
    handler    => sub ($ctx, $n) { ($ctx->{char}->getCol('skill_prospecting') // 0) >= $n },
},
```

### Adding a New Condition or Effect

Adding `selling_gte`:

1. Register in the market visit conditions dispatch table with one sub.
2. Use in YAML:

   ```yaml
   conditions:
     - selling_gte: 2
   ```

No parser changes, no new validation logic. One sub, one line of YAML.

---

## 7. Service: `MagicMountain::Service::RandomEvents`

### Context Shapes

**Prospecting context (`pool => 'prospecting'`):**

```
artifact  — artifact hashref (stage, value, instability, behaviors)
char      — character model object (scrap, score, action_points, skills)
season    — season row hashref (day, length, status, daily_modifiers)
```

**Market visit context (`pool => 'market_visit'`):**

```
customer       — customer hashref (faction_id, irritation, desired_behaviors, ...)
char           — character model object
standing       — hashref { faction_id => N, ... }
faction_state  — hashref { faction_id => { days_since_purchase => N, ... }, ... }
season         — season row hashref
```

**Global context (`pool => 'global'`):**

```
season        — season row hashref (day, length, status, daily_modifiers)
faction_state — hashref { faction_id => { days_since_purchase => N, ... }, ... }
```

### API

**Personal pools** (called from Activity `begin` handlers):

```perl
my $event = $self->app->random_events->draw(
    pool    => 'prospecting',       # or 'market_visit'
    trigger => 'begin',
    char    => $char,
    context => { artifact => $artifact, season => $season },
    seeded_rng => $seed,            # optional: deterministic testing
);
```

**Global pool** (called from `on_maintenance`):

```perl
my $event = $self->app->random_events->draw(
    pool    => 'global',
    trigger => 'day_start',
    context => { season => $season, faction_state => \%faction_state },
);

if ($event) {
    $event->apply($context);            # mutates $season->daily_modifiers hash
    $season->save;                      # persisted; read via Season API during day
    # $event->{text} is passed to the Crier for today's message
}
```

### Selection Algorithm

**Personal pools:**

1. Roll against `event_chance->{pool}->{trigger}` (e.g., `prospecting.begin
   => 0.20`). Return undef if the roll fails — no event fires this action.
2. Load events from `content/events/{pool}.yml`
3. Filter by `trigger` matching the current action boundary
4. Filter by `min_day` / `max_day` against `season.day`
5. Evaluate each event's `conditions` — all must pass (AND)
6. For choice events, evaluate each choice's `conditions`; discard event
   if no choices remain eligible
7. Weighted random selection from remaining events
8. Return the event object (or undef if pool is empty)

**Global pool:**

1. Roll against `global_event_chance` (e.g., 0.60). Return undef if the
   roll fails.
2. Load events from `content/events/global.yml`
3. Filter by `trigger: day_start`
4. Filter by `min_day` / `max_day` against `season.day`
5. Evaluate each event's `conditions` — all must pass (AND)
6. Weighted random selection from remaining events
7. Return exactly one event (or undef if no events eligible)

The `event_chance` and `global_event_chance` values are Perl config, not
YAML. YAML `weight` controls relative probability among eligible events
*after* the Service has decided an event occurs. This keeps YAML from
becoming a probability tuning surface.

### Validation at Load Time

The loader validates every event on startup. Violations die:

**Structural:**
- Top-level YAML must be an array, not a map
- No unknown fields on events or choices
- Every condition/effect map must have exactly one key
- Event `id` must match `^[a-z][a-z0-9_]*$`
- Choice `id` must match the same pattern
- Event IDs unique within pool
- Choice IDs unique within event
- `weight` must be a positive integer
- `text` and choice `labels` must be non-empty and under configured length
- Passive events must have `effects` and no `choices`
- Choice events must have `choices` and no `effects`
- Global events must not have `choices`
- No duplicate effect names within one `effects` list

**Trigger validation:**
- Personal pools (`prospecting`, `market_visit`): only `begin` allowed in v1
- Global pool: only `day_start` allowed

**Value validation:**
- Condition values must be scalars — ranges rejected
- Effect values validated against registry type, bounds, and shape
- Float ranges rejected in v1 (scalar float only)
- Range arrays must have exactly two integers with min ≤ max
- Map-valued effects (`faction_delta`) validated against registered field schemas
- `score_delta` rejected in passive events and non-prospecting pools

**Text validation:**
- Text tokens checked against per-pool whitelist; unknown tokens die

```perl
sub load ($self, $pool) {
    my $yaml = YAML::XS::LoadFile("content/events/$pool.yml");
    die "$pool events must be an array" unless ref $yaml eq 'ARRAY';

    my %seen_ids;
    for my $event (@$yaml) {
        $self->_validate_trigger($event->{trigger}, $pool);
        $self->_validate_weight($event->{weight});
        $self->_validate_day_range($event->{min_day}, $event->{max_day});
        $self->_validate_known_fields($event, $pool);

        die "duplicate event id '$event->{id}'" if $seen_ids{$event->{id}}++;
        die "event id must match ^[a-z][a-z0-9_]*\$" unless $event->{id} =~ /^[a-z][a-z0-9_]*$/;

        for my $cond (@{ $event->{conditions} // [] }) {
            my ($name, $val) = %$cond;
            my $spec = $self->conditions->{$pool}{$name}
                or die "unknown condition '$name' (event '$event->{id}')";
            $self->_validate_value($val, $spec);
            die "conditions may not use ranges (event '$event->{id}')" if ref $val eq 'ARRAY';
        }

        # ... validate effects, choices, text tokens similarly ...
    }
    return $yaml;
}
```

Unknown names, invalid types, out-of-bounds values, range values in
conditions, duplicate IDs, unknown text tokens, wrong triggers, or
structural errors all cause `die` at server startup.

---

## 8. Choice Event Integration

### Activity Flow

When a choice event fires during a `begin` handler:

```
1. Activity handler runs normal logic (draw artifact, generate customer, etc.)
2. Activity calls $service->draw(...)
3. Service returns a choice event ($event->{has_choices} is true)
4. Activity stores event as pending on the activity row
5. Activity returns view with result: 'event', event text, and choices array
6. Player sees event text + choice buttons
7. Player clicks a choice → POST /prospecting/resolve_event with { choice_id: 'strip' }
8. resolve_event handler:
   a. Loads pending event from activity row
   b. Rejects if pending day != current season day (expired at rollover)
   c. Calls $event->apply_choice($choice_id, $context)
   d. Finishes normal action flow
   e. Clears pending event
   f. Returns normal view (ready for push/stop)

### Pending Event Storage

The pending event is stored on the activity row as a snapshot — not as an
event ID lookup reference. This avoids breakage if the YAML is updated
while a player has a pending event:

```json
{
  "pool": "prospecting",
  "event_id": "sealed_battery_case",
  "day": 5,
  "choices": [
    { "id": "strip",   "effects": [{"scrap_delta": [10, 30]}] },
    { "id": "preserve", "effects": [{"scrap_delta": 5}] }
  ]
}
```

`resolve_event` applies the stored choice effects through the current
handler registry. If a handler no longer exists (deploy removed it),
`resolve_event` fails safely and clears the pending event. Pending
events expire at day rollover — the handler rejects `resolve_event`
calls from a prior season day.
```

### Transition Table

```perl
# Prospecting:
has transitions => sub {
    {
        idle       => ['begin'],
        processing => ['push', 'stop', 'resolve_event'],
    }
};
```

`resolve_event` is only valid when a choice event is pending. The handler
dies with "no pending event" if called without one.

### Bot Handling

Bots auto-select the first eligible choice:

```perl
if ($event && $event->{has_choices}) {
    my $choice = $event->{choices}[0];
    $event->apply_choice($choice->{id}, $context);
}
```

### View Contract

**Passive event:**

```perl
{ view => {
    ok       => 1,
    result   => 'start',
    artifact => { stage => 'stable', value => 12, signal => '...' },
    event    => { id => 'seismic_echo', text => 'SENSORY ALERT — ...' },
}}
```

**Choice event:**

```perl
{ view => {
    ok     => 1,
    result => 'event',
    event  => {
        id      => 'sealed_battery_case',
        text    => 'A sealed field case hums weakly...',
        choices => [
            { id => 'strip',   label => 'Strip it for parts',
              action_url => '/prospecting/resolve_event', params => { choice_id => 'strip' } },
            { id => 'preserve', label => 'Preserve the casing',
              action_url => '/prospecting/resolve_event', params => { choice_id => 'preserve' } },
            # 'force_open' not included — player lacks prospecting_gte: 2
        ],
    },
}}
```

The template renders choice buttons using the standard `action_buttons`
component.

---

## 9. Integration Points

| Boundary | Pool File | Trigger | Context | Timing |
|----------|-----------|---------|---------|--------|
| `Prospecting::begin` — after `_apply_defaults`, before save | `prospecting.yml` | `begin` | `artifact`, `char`, `season` | Artifact/char mutated before save |
| `MarketVisit::begin` — after customer gen, before save | `market_visit.yml` | `begin` | `customer`, `char`, `standing`, `faction_state`, `season` | Customer/char mutated before save |
| `on_maintenance` — after AP reset, before bot day-runs | `global.yml` | `day_start` | `season`, `faction_state` | Writes `daily_modifiers`; Activities read them during play |

For choice events at `begin`, effects are deferred until `resolve_event`.

---

## 10. World Feedback (Crier Integration)

### Global Event Narration

When a global event fires, its `text` is passed directly to the Crier as
the day's primary message. Global events ARE the news — they are narrated
by name.

```perl
# In on_maintenance:
my $event = $self->app->random_events->draw(pool => 'global', ...);
if ($event) {
    $event->apply($context);
    $self->app->crier->set_global_event_text($event->{text});
}
```

If no global event fired, the Crier falls back to its normal faction-state
diffing.

### Personal Event Log

Personal events are recorded as daily aggregate counts on the Season model.
The Crier needs counts, not per-event JSON lines:

```json
{
  "day": 5,
  "personal_event_counts": {
    "prospecting": {
      "sealed_battery_case": { "fired": 7, "resolved": 6 },
      "loose_scrap_cache":  { "fired": 3 }
    },
    "market_visit": {
      "desperate_courier": { "fired": 3 }
    }
  }
}
```

Personal events are **never** narrated individually. No player identity
is attached. Per-event JSON line logging can be added later for debugging;
the Crier only consumes the counts.

### Crier Pattern Detection

During daily maintenance, the Crier inspects the personal event log for
aggregate patterns:

| Pattern | Threshold | Crier Template Category |
|---------|-----------|------------------------|
| Same event fired 5+ times in one day | `>= 5` | `events.surge` |
| Prospecting event firing rate up 50% vs previous day | `>= 1.5×` | `events.surge` |
| Market event firing rate down 50% vs previous day | `<= 0.5×` | `events.downturn` |

---

## 11. Bot Integration

**Personal events** — bots hit the same `dispatch()` path. Choice events
auto-resolve to the first eligible choice.

**Global events** — bots read daily modifiers via the Season domain API.
A day with `collapse_chance_mult: 1.25` makes bot artifacts collapse more
often — no code changes, no awareness needed.

---

## 12. Testing Strategy

| Test | What It Covers |
|------|----------------|
| `t/service_random_events.t` | YAML loading, validation (unknown names, bounds, ranges in conditions rejected, text tokens), pool filtering, weighted selection, condition evaluation, range resolution (deterministic with seeded RNG), choice event shape, event_chance rolling |
| `t/prospecting_events.t` | Passive events fire during `begin`, artifact/char mutated. Choice events: view includes choices, `resolve_event` applies chosen effects, gated choices hidden |
| `t/market_visit_events.t` | Events fire during `begin`, customer mutated, ephemeral multipliers applied to sale price |
| `t/prospecting_web.t` | Fragment rendering: passive event text styled as advisory. Choice event buttons rendered, clicked, resolved |
| `bin/smoke_test_endpoint` | `resolve_event` returns 200/400 appropriately |

Every condition and effect handler is a Perl sub under coverage.

---

## 13. Content Authoring Guide

A separate document (`docs/how-to-write-events.md`) will cover soft policies
and conventions for event authors:

- When to use `scrap_delta` vs `score_delta` vs artifact effects
- How to choose weight values relative to other events in the pool
- Day gate pacing: days 1-5 (orientation), 6-15 (depth), 16-25 (pressure),
  26-30 (endgame)
- Text style conventions (PB3K framing, advisory tone, length limits)
- How to test an event locally with seeded RNG before committing
- When to make a passive event vs a choice event
- Skill gate philosophy: gates should reward investment, not gatekeep
  basic content

This is a living document maintained by whoever authors the most recent
event. The technical spec you're reading now defines what the system can
do; the how-to doc defines what it *should* do.

---

## 14. Comparison with Existing Events Design

| Concern | docs/Events.md | This Design |
|---------|----------------|-------------|
| Infrastructure | Event engine class, `content/events/` dir, State mutations | Single Service, one YAML file per pool, no new models |
| Player interaction | Choice-based (multiple outcomes) | Both passive and choice-based |
| Turn economy | Interrupts consume a prospecting turn | No turn cost |
| Persistence | Outcome mutations on State | Transient — baked into existing persisted state |
| Logic location | Unspecified | Dispatch table in Perl; YAML references names only |
| Skill gates | Not specified | Conditions with `prospecting_gte` etc. — no special fields |
| World feedback | Unspecified | Global events narrated directly; personal events aggregate-only |
| Content authoring | `content/events/` directory | `content/events/{pool}.yml` — one file per pool |
| V1 surface | Not specified | `trigger: begin` and `trigger: day_start` only |
