# Magic Mountain — Random Events

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

3. **Zero new infrastructure** — No event engine, no `content/events/`
   directory, no new model classes. A single Service class
   (`Service::RandomEvents`) that Activities call at action boundaries.

4. **PB3K framing** — Events appear as device sensor readings, system
   advisories, or environmental readings — never as game-UI "notifications."
   This is consistent with the device-fiction constraint (GAME_ARCHITECTURE.md §1.1).

5. **World feedback loop** — Events that fire are recorded to a daily event
   log. During maintenance, the Crier checks for significant event patterns
   (e.g., many players hitting the same event type) and generates world-
   condition narrative. This connects per-player events to the wider
   fictional world without requiring global state.

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

---

## 3. YAML Structure

File: `content/flavor/events.yml`

```yaml
prospecting_events:
  - id: seismic_echo
    weight: 8
    trigger: begin
    min_day: 3                     # optional: only fire after day N
    max_day: null                  # optional: only fire before day N
    condition: null                # optional: Perl expression evaluated against context
    skill_min: null                # optional: requires skill level >= N
    skill_max: null                # optional: requires skill level <= N
    text: "SENSORY ALERT — Low-frequency resonance detected. Substrate analysis suggests a dense pocket nearby."
    effects:
      - adjust_value: 4            # +4 to artifact base_value

  - id: unstable_pocket
    weight: 5
    trigger: begin
    text: "STABILITY WARNING — Localized field distortion. Artifact containment may be compromised."
    effects:
      - adjust_instability: 2      # +2 to artifact starting_instability

  - id: containment_leak
    weight: 6
    trigger: push
    condition: "artifact.stage eq 'unstable'"
    text: "CONTAINMENT ALERT — Cascading field collapse in progress. Instability spike detected."
    effects:
      - scale_instability: 1.5     # multiply current artifact instability

  - id: rich_vein
    weight: 3
    trigger: push
    text: "YIELD ANALYSIS — Unexpected secondary payload detected. Value projection revised upward."
    effects:
      - adjust_value_gain: 3       # +3 to this push's value gain (before skill modifiers)

  - id: secondary_signal
    weight: 4
    trigger: begin
    text: "ANOMALY DETECTED — Artifact appears to have a secondary behavioral signature."
    effects:
      - add_behavior: "signal"     # adds an extra behavior tag to the artifact

  - id: mountain_exhales
    weight: 2
    trigger: begin
    max_day: 15
    text: "GEOPHYSICAL EVENT — The mountain vents. A loose artifact surfaces nearby."
    effects:
      - no_ap_cost: 1              # refund 1 AP (effectively -1 AP cost for this begin)

sales_events:
  - id: desperate_courier
    weight: 8
    trigger: begin
    condition: "faction_state[char.current_customer].days_since_purchase >= 3"
    text: "INCOMING TRANSMISSION — {faction_name} courier dispatching priority procurement. Backlog rates in effect."
    effects:
      - multiplier_bonus: 0.25     # +0.25 to effective multiplier

  - id: flooded_market
    weight: 5
    trigger: begin
    text: "MARKET ANALYSIS — Elevated supply detected in local inventory. Buyer leverage increased."
    effects:
      - multiplier_penalty: -0.15  # -0.15 to effective multiplier

  - id: generous_buyer
    weight: 4
    trigger: offer
    condition: "outcome eq 'match'"
    text: "NEGOTIATION LOG — Buyer appears unusually satisfied with the match. Adjusting valuation upward."
    effects:
      - match_premium: 1.15        # 1.15x on top of match multiplier

  - id: thin_skinned
    weight: 4
    trigger: begin
    text: "PSYCH PROFILE — Buyer flagged as irritable. Recommend measured approach."
    effects:
      - irritation_floor: 2        # customer starts with +2 irritation

  - id: faction_bounty
    weight: 5
    trigger: begin
    condition: "standing[current_customer] >= 2"
    text: "NOTICE — {faction_name} has posted a procurement bonus for repeat partners. Standing recognized."
    effects:
      - standing_bonus_mult: 1.1   # bonus multiplier based on standing
```

### Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `id` | yes | — | Unique identifier for the event |
| `weight` | yes | — | Relative probability (higher = more likely) |
| `trigger` | yes | — | `begin`, `push`, or `offer` |
| `min_day` | no | null | Only fire on or after this season day |
| `max_day` | no | null | Only fire on or before this season day |
| `condition` | no | null | Optional stringified Perl expression evaluated against context |
| `skill_min` | no | null | Requires character's relevant skill >= this level |
| `skill_max` | no | null | Requires character's relevant skill <= this level |
| `text` | yes | — | Player-facing flavor text (may contain `{placeholder}` substitutions) |
| `effects` | yes | — | Array of effect maps (see §4) |

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

### Construction

```perl
# MagicMountain.pm startup:
has random_events => sub ($self) {
    MagicMountain::Service::RandomEvents->new(
        file => $self->home . '/content/flavor/events.yml',
        app  => $self,
    )->load_content;
};
```

### API

```perl
# Draw an event from the pool, return undef if none fire
my $event = $self->app->random_events->draw(
    pool   => 'prospecting',    # or 'sales'
    char   => $char,            # Model::Character
    context => {                # action-specific state
        artifact      => $artifact,
        customer      => $customer,
        season        => $season,
        standing      => \%standing,
        faction_state => \%faction_state,
    },
);

if ($event) {
    $event->apply($context);     # mutates artifact/customer in-place
    $self->event_text($event->text);  # stored ephemerally for the view
}
```

### Selection Algorithm

1. Filter pool by `trigger` matching the current action
2. Filter by `min_day` / `max_day` against `season.day`
3. Filter by `skill_min` / `skill_max` against character's relevant skill
4. Evaluate `condition` (Perl expression in a sandboxed eval against context)
5. If no events remain, return undef
6. Weighted random selection from remaining events
7. Return the selected event (or undef if none match)

The Service also exposes `pool_size($pool, $context)` for testing — returns
count of eligible events after all filters.

### View Integration

The Activity includes event text in its view hashref:

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

The template renders `event.text` if present, always below the primary
outcome text, styled as a PB3K system advisory (amber `WARNING` / `ALERT` /
`NOTICE` header). Never styled as game UI.

---

## 6. World Feedback (Crier Integration)

### Daily Event Log

Each event that fires is recorded to a lightweight event log on the Season
model (or a separate `events_log` column as a JSON array). Entry shape:

```json
{
  "event_id": "seismic_echo",
  "day": 5,
  "pool": "prospecting",
  "timestamp": 1717000000
}
```

Entries are append-only. No player identity attached — the system records
aggregate event frequency, not per-player attribution.

### Crier Pattern Detection

During daily maintenance (`on_maintenance` callback), after faction-state
diffing, the Crier inspects the event log for patterns:

| Pattern | Threshold | Crier Template Variable |
|---------|-----------|------------------------|
| Same event fired 5+ times in one day | `>= 5` | `{event_frequency}` |
| Prospecting event firing rate up 50% vs previous day | `>= 1.5×` | `{activity_surge}` |
| Sales event firing rate down 50% vs previous day | `<= 0.5×` | `{market_downturn}` |

When triggered, the Crier selects from an `events` message category in
`content/flavor/crier.yml`:

```yaml
crier_messages:
  events:
    surge:
      - "SEISMIC READINGS elevated across the basin. Multiple teams reporting anomalous signatures."
      - "The mountain is restless today. Sensor interference widespread."
    downturn:
      - "Market activity quiet. Buyers maintaining position."
      - "Procurement volumes down. Faction representatives scarce."
```

This keeps world feedback textual and atmospheric — no direct link between
"event X fired N times" and a specific mechanical global effect. The Crier
reports what the PB3K network is seeing; the player draws their own
conclusions.

The event log is cleared after Crier generation (it represents one day's
activity). If no significant patterns are detected, the Crier uses its
normal faction-diff fallback.

---

## 7. Bot Integration

Bot policies need no changes. The event service fires automatically during
the Activity's `dispatch`, which bots call identically to human players.
Event flavor text is simply discarded by the bot's response handler — the
mechanical effect is already applied.

For simulation analysis, the transcript already records each action. The
`event` field in the Activity's view could be captured as a transcript
event type (`random_event`) if analysis of event impact is needed. This is
optional and can be added later.

---

## 8. Testing Strategy

| Test | What It Covers |
|------|----------------|
| `t/random_events.t` | Service unit tests: YAML loading, pool filtering, weighted selection, effect application, condition evaluation |
| `t/prospecting_events.t` | Integration: events fire during `begin`/`push`, artifact is mutated, view includes event text |
| `t/sales_events.t` | Integration: events fire during `begin`/`offer`, customer is mutated, view includes event text |
| `t/prospecting_web.t` / `t/market_visit_web.t` | Fragment rendering: event text appears in HTML, styled as advisory |
| `bin/smoke_test_endpoint` | No new endpoints needed — events piggyback on existing action responses |

---

## 9. Comparison with Existing Events Design

The existing `docs/Events.md` describes a heavier system with choice-based
interrupt events, an event engine, and turn-consuming events. The design
here is intentionally simpler:

| Concern | Existing Design (docs/Events.md) | This Design |
|---------|----------------------------------|-------------|
| Infrastructure | Event engine class, content/events/ dir, State mutations | Single Service, one YAML file, no new models |
| Player interaction | Choice-based (multiple outcomes) | Passive (immediate effect) |
| Turn economy | Interrupts consume a prospecting turn | No turn cost (fires alongside action) |
| Persistence | Outcome mutations on State | Transient — effect baked into existing persisted state |
| World feedback | Unspecified | Crier pattern detection from event log |

Both designs could coexist: the lightweight system here handles the
"ambient atmosphere + small mechanical surprise" slot. The heavier choice
system (if implemented later) would handle structured narrative events.
