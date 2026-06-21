# Magic Mountain — Game Architecture

*Intended as a specification for rebuilding this game on a new foundation.
No source code. All mechanics, boundaries, and invariants preserved.*

> **Rails conventions applied where fitting**: Thin controllers (dispatch + render
> only), fat models with invariant enforcement, activities that own their own
> persistence (`save`, `delete` on the instance), and a separation of concerns
> that mirrors ActiveRecord's controller/model boundary. This is a Perl codebase
> with a Rails-inspired architecture — not a port.

---

## 1. Game Concept

**Magic Mountain** is a multiplayer seasonal push-your-luck game. Players extract
strange artifacts from a mysterious mountain, destabilize ("push") them for
greater value (risking catastrophic collapse), store them in a shed where they
decay, and negotiate sales with visiting faction buyers at the Bazaar. Each
season is a tournament: highest cumulative sale value wins.

**Core tension**: Every "push" (destabilization attempt) increases an artifact's
value but also raises its risk of catastrophic collapse. Collapse means total
loss — zero salvage. Players must also manage decaying inventory, limited
action points per day, and fleeting market opportunities.

**Player role**: The player is an opportunistic salvager — never a savior,
never a villain. The game does not morally categorize the player.

---

## 2. Core Gameplay Loop

```
Login/join season
  → Each day: 15 Action Points (AP)
    → Prospecting (costs 2 AP)
      → Artifact is drawn from weighted pool
      → Push (repeatable, no AP cost)
        → Instability grows, value grows
        → Three stages: stable → strained → unstable
        → Possible outcomes:
          - Collapse: lose artifact, get nothing
          - Breakthrough: artifact evolves, massive value spike, auto-cashout
          - Normal: value increases, new signal text
      → Stop (no AP cost)
        → Artifact enters Shed with estimated value range
        → Activity cleared

    → Market Visit (costs 1 AP)
      → Customer/buyer appears with hidden demand
      → Player may offer any artifact from Shed
      → Negotiation may succeed (sale) or fail (customer leaves)
      → On sale: scrap + score awarded, artifact removed from Shed

    → Skill Training (no AP cost, costs scrap)
      → Buy or upgrade seasonal skills

  → Day rollover: refresh AP, artifact decay tick, season day increments
  → Season ends after N days (admin-triggered)
```

### Key structural rules:
- Prospecting and selling are **separate activities** with different AP costs.
  Prospecting costs 2 AP. Market visits cost 1 AP.
- Artifacts enter the Shed after prospecting. Selling happens later, possibly
  on a different day.
- AP are refreshed fully at day rollover. Unused AP are lost.
- Skill training does not cost AP but costs scrap.

---

## 3. Architecture: Two-Phase Design

The application operates in two distinct phases. They share a persistence layer
but never overlap in time.

### 3.1 Phase 1: Player Actions (HTTP)

Controllers are thin adapters between HTTP and the game. They extract player
identity from the session, load models, delegate to activities, and pipe
results to the view. Zero game logic. Zero phase validation. Zero persistence
coordination.

Activities are persisted entities (extending `MagicMountain::Model`) stored in
`activities.json`, linked to characters via a `pending_activity_id` foreign key.
The global activity instance (e.g. `$app->prospecting`) owns the persistence table
and loaded content; per-request activity rows are loaded or created via standard
Model `get()`/`create()`.

```
Browser → Mojo route → Controller action
                          │
                          ├── Resolve player identity ($c->current_player)
                          ├── Load character model (Model::Character)
                          ├── Read pending_activity_id from character
                          ├── Load or create activity row:
                          │     $id = $char->getCol('pending_activity_id')
                          │     $activity = $id ? $app->prospecting->get($id)
                          │                     : $app->prospecting->create(char_id => $char->getCol('id'))
├── Delegate: $activity->dispatch($char, $action, %params)
│     │
│     ├── Activity base: read $self->phase (column), validate transition
│     ├── Validate handler exists ($self->can($action))
│     ├── Activity subclass: execute game math
│     ├── Mutate $char fields via setCol (scrap, score, action_points)
│     ├── Persist: $self->save; $char->save
│     │   (If terminal outcome: delete own row, clear FK, save $char)
│     └── Return { view => {...} }
│
└── Pipe $result->{view} to render/json
```

Controllers are dumb pipes. They do not inspect or filter what the activity
returns. They trust `action_points` as written by maintenance — no rollover
checks, no clock advancement.

### 3.2 Phase 2: Daily Maintenance (In-Process)

Maintenance runs as an in-process timer (Mojo::IOLoop recurring every 60
seconds) managed by `MagicMountain::Maintenance`. When the configured
`end_of_day_hour` arrives, the maintenance window fires: it sets an
`in_maintenance` flag, invokes the `on_maintenance` callback for day-rollover
logic, then clears the flag. No external cron or separate CLI invocation is
needed.

```
Mojo::IOLoop (every 60s) → Maintenance::dailyMaintenance
  │
  ├── Check: is it time? (compare now against next_run)
  ├── Set in_maintenance flag (gates write routes → HTTP 503)
  ├── Advance next_run to next day
  ├── Invoke on_maintenance callback
  │     (extension point for: increment season.day, refresh AP,
  │      apply artifact decay, update leaderboard, check season end)
  └── Clear in_maintenance flag
```

**Route gating**: During the maintenance window, public read-only routes
(`GET /`, `/login`, `/logout`, `DELETE /sessions`) remain available. All
write routes and authenticated routes return HTTP 503. This is enforced via
a Mojolicious `under` bridge that checks the `is_maintenance` helper.

### 3.3 Why Not Separate Process?

A standalone CLI-based approach (cron-triggered `advance-day`) was considered
and replaced with the in-process timer because:

- Maintenance needs to interact with the running app's route gating — setting
  `in_maintenance` requires sharing process memory.
- An external cron job would need to signal the running process (via file
  lock, PID file, or HTTP endpoint), adding complexity without value.
- The Mojo::IOLoop timer provides precise per-second scheduling without
  external infrastructure (no crontab to configure, no separate deployment).
- The actual day-rollover logic (AP refresh, day increment, decay) runs in the
  `on_maintenance` callback — a single responsibility extension point that
  keeps maintenance concerns isolated from controllers.

### 3.4 Why Not an Engine?

A central "Engine" coordinator class was considered and rejected. The deeper
reason goes beyond convenience:

**Mojolicious is already the application lifecycle root.** `MagicMountain.pm`
is not a passive dependency container — Mojolicious provides an event loop,
HTTP request dispatch, lifecycle hooks, timers/recurring tasks, and test
harness integration out of the box. Adding a separate `Engine` class on top
of that would create an artificial "application inside the application" — a
second coordinator layered over one that already exists.

**The real architectural rule is not "all gameplay must go through Engine."**
It is: *gameplay behavior must not leak into controllers, raw state hashes,
timers, or persistence plumbing.* That rule is satisfied by focused service
classes (Activity, Market, Shed, Model::Character) without a central dispatcher.

**Daily maintenance is an application lifecycle concern, not an ad hoc game
action.** Mojolicious is the correct place to schedule it. The maintenance
behavior lives in a dedicated, directly-testable class (`Maintenance.pm`)
invoked by the app's timer.

**A single coordinator would couple unrelated concerns.** HTTP request handling
and scheduled maintenance have different callers, different concurrency needs,
and different failure modes. Routing them through a single `Engine` would force
the class to serve two masters.

**So why would Engine ever earn its keep?** Only if a concrete coordination
responsibility emerged that was not already naturally handled by the
Mojolicious app lifecycle plus service objects — for example, a reusable
transaction boundary shared by HTTP, CLI, simulation, and test runners.
No such gap exists: models persist themselves, activities own their
read-modify-write cycles, and the app class wires everything together.

**The risk is not that `MagicMountain.pm` coordinates.** The risk is that it
becomes a god object full of game mechanics. The defense is simple: keep
mechanics in focused service classes, keep the app class as a thin lifecycle
root. A separate Engine is redundant ceremony, not a guardrail.

---

## 4. Module Boundary Table

Each module has strict constraints on what it may and must never hold.

| Module | May Hold | Must NEVER Hold |
|--------|----------|-----------------|
| **Controller::*** | App reference, model accessors (accounts, characters, seasons, shed, skills) | Game logic, phase validation, artifact math, persistence orchestration |
| **Activity (base)** | Persisted columns, ephemeral attributes (transitions, app, content), dispatch logic | Game math, artifact knowledge, YAML content interpretation |
| **Activity::Prospecting** | App reference, transition table, content interpretation, live activity state (artifact) | Market logic, Shed offers, other players' data |
| **Activity::MarketVisit** | App reference, transition table, negotiation state, customer data | Prospecting logic, artifact push math |
| **Shed** (inventory manager) | ShedItem rows, decay logic, query/filter by traits | Market, Faction objects, Account model |
| **Market** (customer generator) | Faction objects, content reference, customer generation | Character model, Account model, Shed |
| **Model::Character** | File path, column definitions, JSON CRUD, invariant enforcement (AP bounds, scrap≥0, score never decreases, skills 0–3) | Market, Faction, Content, Shed, game math, artifact logic |
| **Model::ShedItem** | File path, column definitions, JSON CRUD | Game logic, decay math, faction rules |
| **Model::Character** | File path, column definitions, JSON CRUD | Game logic, artifact math, faction rules |
| **Model::Account** | File path, column definitions, JSON CRUD | Game logic, season data, character data |
| **Model::Season** | File path, column definitions, JSON CRUD | Per-player character data, game logic |
| **Model::Session** | File path, column definitions, expiry logic | Game logic, character data |
| **Model::Skill** | File path, column definitions, JSON CRUD | Game logic, character state |
| **Maintenance** | App reference, end_of_day_hour, clock, on_maintenance callback | Game math, artifact logic, character internals |
| **Content** (YAML loader) | Directory path, parsed YAML data | Model persistence, game rules |
| **Transcript** (event recorder) | File handle, app reference (for request context) | Game rules, account management |
| **Faction** (buyer definition) | ID, name, multiplier, interests, disposition | Character data, player identity |
| **Bot** (automated player) | Policy name, parameters, activity access | Direct persistence (uses same models and activities as controllers) |

### Constructor Checklist for Activity Subclasses

An Activity subclass receives:
- **file** — path to `activities.json` (persistence table, inherited from Model)
- **app** — application reference (for logging)
- **content_filename** — full path to the activity's YAML content file
- **log** — logger trampoline (defaults to `$self->app->log`)

The global instance (e.g. `$app->prospecting`) is constructed once at startup and
calls `load_content` to parse the YAML file into `content_data`. Per-request
activity rows are created via `$prospecting->get($id)` or
`$prospecting->create(%params)` — these inherit `transitions`, `app`, and
`content_data` from the global instance automatically (via overridden `get`/`create`
in the base class).

The subclass declares:
- **transitions** — hashref where keys ARE the phases, values are arrays of legal actions
- **create** override — sets type/phase column defaults, chains to Activity::create
- Handler methods (e.g. `begin`, `push`, `stop`) — one per action in the transition table

### Controller Responsibility

Controllers are dumb pipes. Their entire job:

1. Resolve player identity via `$self->current_player`
2. Load the character model via `$self->app->characters->find(...)`
3. Read `pending_activity_id` from the character
4. Load or create the activity row:
   - `$id = $char->getCol('pending_activity_id')`
   - `$activity = $id ? $self->app->prospecting->get($id) : $self->app->prospecting->create(char_id => $char->getCol('id'))`
5. Delegate to the activity: `$activity->dispatch($char, $action, %params)`
6. Pipe the activity's `view` result to the template: `$self->render(json => $result->{view})`

No phase validation. No game math. No persistence orchestration. No transcript
recording. The activity handler owns all persistence — character saves, activity
saves, row deletion, shed item creation. Controllers trust `action_points` as
written.

---

## 5. Data Model

### 5.1 PlayerAccount (permanent identity)

| Field | Type | Description |
|-------|------|-------------|
| player_id | UUID | Primary key |
| display_name | string | Unique, user-chosen |
| created_at | timestamp | Account creation time |

Survives across seasons. Contains no gameplay data.

### 5.2 Season (tournament)

| Field | Type | Description |
|-------|------|-------------|
| season_id | UUID | Primary key |
| label | string | Human-readable (e.g., "Season 1") |
| status | enum | upcoming / active / archived |
| day | integer | Current season day (starts at 1) |
| started_at | timestamp | When season went active |
| ended_at | timestamp | When season was finalized |
| faction_state | map | Per-faction influence and artifacts_received counts |

### 5.3 Model::Character (one per player per season)

| Field | Type | Description |
|-------|------|-------------|
| player_id | UUID | FK to PlayerAccount |
| season_id | UUID | FK to Season |
| display_name | string | Snapshot of name at season start |
| score | integer | Cumulative leaderboard value from sales. NEVER decreases |
| scrap | integer | Spendable currency. Decreases via skill purchases |
| action_points | integer | Current AP remaining for the day |
| action_points_max | integer | Daily AP cap (default 15) |
| faction_sales | map | Per-faction sale count this season |
| standing | map | Per-faction reputation integer |
| pending_activity_id | string or null | FK to activities.json row. null when idle |
| skill_prospecting | integer | 0–3, Prospecting skill level |
| skill_upcycling | integer | 0–3, Upcycling skill level |
| skill_selling | integer | 0–3, Selling skill level |
| current_location | string | Current location ID in the location graph (default: `camp`) |

> `turns_remaining` has been replaced by `action_points` / `action_points_max`.
> The old "lazy rollover" design using `last_refreshed_day` was already removed
> in favor of in-process maintenance AP refresh.

**Invariants enforced by Model::Character:**
- `action_points` cannot go below zero and cannot exceed `action_points_max`
- `scrap` must be non-negative
- `pending_activity_id` must reference a valid activities.json row if set
- `score` never decreases
- Attempting to start a prospecting or market activity without sufficient AP
  is a hard error
- Skills are 0–3, inclusive

**Property distinction:**
- `score` = cumulative seasonal leaderboard value from artifact sales, never decreases
- `scrap` = spendable seasonal currency, may decrease through skill purchases

### 5.4 ShedItem (shed.json)

Each row represents one artifact recovered from prospecting, stored in the
player's shed pending sale or decay.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| char_id | UUID | FK to character |
| artifact_id | string | Original artifact spec ID (e.g. "thermal_box_001") |
| original_value | integer | Value at stop time (post-push, pre-decay) |
| decayed_value | integer | Current estimated value after decay |
| condition | enum | fresh / settling / fading |
| days_in_shed | integer | Number of decay ticks applied |
| instability | integer | Final instability at stop time |
| stage | string | Final stage at stop time (stable/strained/unstable) |
| push_count | integer | Number of pushes applied |
| has_evolved | boolean | Whether breakthrough occurred |
| behaviors | arrayref | Trait tags copied from artifact spec |
| archetypes | arrayref | Thematic grouping copied from artifact spec |
| estimated_value_min | integer | Lower bound shown to player |
| estimated_value_max | integer | Upper bound shown to player |
| created_at | timestamp | When the artifact entered the shed |
| updatedAt | timestamp | Last save time |

The `behaviors` array is the key field for faction interest matching during
market negotiation. Copied from the artifact spec at stop time so that the
shed item is self-contained.

### 5.5 Activity (activities.json)

Each active game session is a row in the activities table. The character's
`pending_activity_id` column is an FK to this table. When the activity phase
returns to `'idle'`, the row is deleted and the FK cleared.

**Table: activities.json**

```
{
  "<uuid>": {
    "id": "<uuid>",
    "char_id": "<uuid>",
    "type": "prospecting",
    "phase": "processing",
    "artifact": { ... },
    "customer": null,
    "createdAt": <unix_ts>,
    "updatedAt": <unix_ts>
  }
}
```

**Columns** (all JSON-serialized by Model):

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| char_id | UUID | FK to characters.json |
| type | string | Discriminator: "prospecting" or "market_visit" |
| phase | string | State-machine phase (varies by type) |
| artifact | hashref or null | Live artifact state (prospecting only, null when idle) |
| customer | hashref or null | Current customer state (market_visit only, null when idle) |
| createdAt | unix timestamp | Row creation time |
| updatedAt | unix timestamp | Last save time |

The `offers` column is removed — selling no longer happens inside a
prospecting activity. Offers are replaced by the negotiation flow in the
MarketVisit activity.

**Prospecting — artifact column shape** (same as before):

```json
{
  "id": "thermal_box_001",
  "value": 24,
  "instability": 5,
  "stage": "strained",
  "push_count": 3,
  "max_instability": 14,
  "instability_growth_min": 1,
  "instability_growth_max": 2,
  "base_gain_min": 3,
  "base_gain_max": 5,
  "can_evolve": true,
  "has_evolved": false,
  "evolution_threshold": 0.25,
  "evolution_chance": 0.03,
  "evolution_instability_spike": 2,
  "breakthrough_multiplier_min": 1.5,
  "breakthrough_multiplier_max": 2.0,
  "state_thresholds": { "stable": 0.35, "strained": 0.70 }
}
```

**MarketVisit — customer column shape** (during negotiating phase):

```json
{
  "faction_id": "syndicate",
  "faction_name": "The Syndicate",
  "desired_behaviors": ["thermal", "storage", "power"],
  "base_multiplier": 1.1,
  "irritation": 0,
  "irritation_threshold": 5,
  "settle_chance": 0.15,
  "offer_value": null,
  "offer_text": null
}
```

### 5.6 SeasonFactionState (per-season global faction tracking)

| Field | Type | Description |
|-------|------|-------------|
| faction_id | string | FK to faction definition |
| season_id | UUID | FK to Season |
| influence | integer | Accumulated value from all sales to this faction |
| artifacts_received | integer | Count of artifacts sold to this faction |
| intake_by_trait | map | Map of trait → count received (e.g. `{thermal: 5, signal: 2}`) |
| market_saturation | map | Map of trait → saturation level (affects future pricing) |

Planned. Will drive faction dominance, Crier reports, buyer context, and
market dynamics.

### 5.7 ArtifactDisposition (per-sale record) — Planned

| Field | Type | Description |
|-------|------|-------------|
| disposition_id | UUID | Primary key |
| season_id | UUID | FK to Season |
| player_id | UUID | FK to PlayerAccount |
| faction_id | string | Which faction bought it |
| season_day | integer | When the sale occurred |
| value_awarded | integer | Final sale value |
| artifact_snapshot | JSON | Full artifact state at sale time (copied from shed item) |
| standing_delta | integer | Standing change from this sale |
| influence_delta | integer | Influence added to faction |
| narrative_hooks | JSON | Keys for future Crier/narrative generation |

Not yet implemented. Append-only. Immutable after creation. Survives character
deletion.

### 5.8 SeasonRecord (post-season archive)

| Field | Type | Description |
|-------|------|-------------|
| record_id | UUID | Primary key |
| season_id | UUID | FK to Season |
| player_id | UUID | FK to PlayerAccount |
| final_score | integer | Season-ending score |
| final_scrap | integer | Season-ending scrap |
| rank | integer | Final leaderboard position |
| faction_standing_snapshot | JSON | Standing at season end |
| skills_snapshot | JSON | Skill levels at season end |
| story_highlights | JSON | Notable dispositions and narrative hooks |
| created_at | timestamp | When finalized |

Created during season finalization, before characters are deleted.

### 5.9 Skill Definition (content/skills.yml, loaded by Model::Skill)

Skills are defined in YAML content, not hardcoded:

```yaml
- id: prospecting
  name: Prospecting
  max_level: 3
  levels:
    - level: 1
      cost: 10
      description: "Better leads"
    - level: 2
      cost: 25
      description: "Richer veins"
    - level: 3
      cost: 50
      description: "Eye for the unusual"
- id: upcycling
  name: Upcycling
  max_level: 3
  levels:
    - level: 1
      cost: 10
      description: "Firm touch"
    - level: 2
      cost: 25
      description: "Steady hand"
    - level: 3
      cost: 50
      description: "Master's feel"
- id: selling
  name: Selling
  max_level: 3
  levels:
    - level: 1
      cost: 10
      description: "Better haggling"
    - level: 2
      cost: 25
      description: "Customer reader"
    - level: 3
      cost: 50
      description: "Dealmaker"
```

The `cost` field is in scrap. Exact mechanical effects per level are marked
as implementation detail — see section 6.6.

### 5.10 Entity Lifecycle

```
PlayerAccount ─── persists forever ──────────────────────►
       │
       ├── Season 1 ─── SeasonalCharacter ──► deleted ──►
       │                     │
       │                     ├── ShedItem (created after prospecting stop)
       │                     ├── Skill levels (bought with scrap, columns on character)
       │                     ├── Activity (created/loaded per request, deleted on idle)
       │                     └── ArtifactDispositions (survive)
       │
       ├── Season 2 ─── SeasonalCharacter ──► deleted ──►
       │
       └── SeasonRecords (permanent archive)
```

A SeasonalCharacter may be deleted ONLY after:
1. Season finalization creates a SeasonRecord
2. All SeasonRecords are verified as stored
3. All owned ShedItems are discarded (artifacts are forfeit at season end)
4. Then hard-deletion is permitted

---

## 6. Game Mechanics

### 6.1 Artifact Drawing

Artifacts are selected via weighted random selection from the YAML content
pool. Each artifact spec has a `weight` field. Total weight sums across all
specs, and a random roll selects one.

The Prospecting skill level may influence the draw pool or base parameters
(see 6.6 for skill effects marked as implementation detail).

### 6.2 Push Model (Artifact Destabilization)

Each push operation:

1. **Increment push_count**

2. **Instability growth**: `growth = instability_growth_min + random_int(0, instability_growth_max - instability_growth_min)`
   - The random component uses a uniform distribution for the integer range

3. **Stage determination**: `ratio = instability / max_instability`
   - `ratio <= stable_threshold` → "stable"
   - `ratio <= strained_threshold` → "strained"
   - `ratio > strained_threshold` → "unstable"

4. **Collapse check**: `collapse_chance = (ratio³) × 0.95`
   - Clamped to minimum 5% and maximum 100%
   - Roll uniform random [0,1); if roll < collapse_chance → **COLLAPSE**
    - Collapse is total loss: artifact destroyed, player gets nothing,
      activity row deleted

5. **Evolution check** (only if collapse did not occur, `can_evolve` is true,
   `has_evolved` is false, AND `ratio >= evolution_threshold`):
   - Roll uniform random [0,1); if roll < `evolution_chance` → **BREAKTHROUGH**
   - A breakthrough immediately cashes out:
     - `has_evolved` set to true
     - `mult = breakthrough_multiplier_min + random_float × (breakthrough_multiplier_max - breakthrough_multiplier_min)`
     - `new_value = floor(artifact.value × mult)`
     - Artifact value set to new_value
     - Instability increases by `evolution_instability_spike`
     - Player receives `new_value` as both scrap and score
      - Activity row deleted (no stop needed, artifact never enters shed)
     - At most ONE evolution per artifact

6. **Value gain** (if no collapse and no breakthrough):
   - `gain = base_gain_min + random_int(0, base_gain_max - base_gain_min)`
   - `artifact.value += gain`
   - A random signal text is selected from the YAML spec for the current stage

### 6.3 Stop and Shed Entry

When a player stops (not collapse, not breakthrough):

1. AP cost was already deducted at `begin` — stop does not cost additional AP
2. An estimated value range is calculated from the artifact's current value:
   - `estimated_value_min = floor(value × 0.8)`
   - `estimated_value_max = floor(value × 1.2)`
   - (May be influenced by Selling skill — see 6.6)
3. A ShedItem is created with:
   - Artifact spec data copied into `artifact_id`, `behaviors`, `archetypes`
   - Current artifact state copied into `original_value`, `instability`, `stage`, `push_count`, `has_evolved`
   - `decayed_value` set to `original_value` initially
   - `condition` set to `fresh`
   - `days_in_shed` set to 0
   - `estimated_value_min` and `estimated_value_max` from step 2
4. The activity row is deleted and `pending_activity_id` is cleared
5. Player receives estimated value range as information only (no scrap or score yet)

No buyer offers are generated at stop time. Selling is a separate activity.

### 6.4 Artifact Decay

Decay is applied during daily maintenance. For each ShedItem:

1. Increment `days_in_shed` by 1
2. Determine condition based on `days_in_shed`:
   - 0–1 days: `fresh`
   - 2–4 days: `settling`
   - 5+ days: `fading`
3. Recalculate `decayed_value`:
   - `fresh`: 100% of `original_value`
   - `settling`: 75% of `original_value`
   - `fading`: 40% of `original_value`
   - These multipliers may be adjusted by artifact traits (e.g., thermal
     artifacts decay faster, signal artifacts decay slower)
4. Update `estimated_value_min` and `estimated_value_max` proportionally

**Trait-specific decay** (future refinement):
- `thermal`, `food_processing`: decay faster (fresh → settling after 1 day,
  settling → fading after 2 days)
- `signal`, `revelation`, `field`: decay slower (fresh → settling after 2 days,
  settling → fading after 4 days)
- `unstable`: becomes more hazardous (may increase value for Purifiers,
  decrease for others)

**Decay does not destroy artifacts.** Even `fading` artifacts can be sold,
typically at reduced value. Certain factions (Purifiers, Revelationists) may
prefer or even pay premiums for decayed artifacts.

### 6.5 Market Negotiation (Customer-First Selling)

When a player starts a Market Visit (costs 1 AP):

1. **Customer generation**: A customer is generated from the eligible faction
   pool, with:
   - `faction_id`, `faction_name`
   - `desired_behaviors` — a subset of the faction's interests (hidden from player)
   - `base_multiplier` — the faction's standard offer multiplier
   - `irritation` — starts at 0
   - `irritation_threshold` — if exceeded, customer leaves
   - `settle_chance` — probability the customer will accept a non-matching item

2. **Player offer**: Player selects an artifact from their Shed and presents it
   to the customer. The negotiation logic:
   - If artifact behaviors intersect desired_behaviors:
     - **Match**: High offer at `floor(decayed_value × base_multiplier × match_bonus)`
       where `match_bonus` is determined by the number/strength of matching traits.
       Positive narrative response. Irritation unchanged (or decreases).
   - If no intersection:
     - **Mismatch**: Low offer at `floor(decayed_value × base_multiplier × 0.5)`.
       Negative narrative response. Irritation increases by 1-2.
   - On match OR mismatch, the player may:
     - **Accept**: Sale occurs — `offer_value` added to scrap and score,
       artifact removed from Shed, customer leaves satisfied.
     - **Counter-offer** (future): Negotiate for a better price.
     - **Show another artifact**: Repeat offer step with a different shed item.
     - **Send away**: No sale. Artifact remains in shed. Customer leaves. Market
       Visit AP is consumed.

3. **Customer leaves** if:
   - A sale is agreed (success)
   - Irritation exceeds threshold (failure — customer storms off)
   - Player sends the customer away (neutral — no sale)
   - Rare settle: on mismatch, a random roll against `settle_chance` may cause
     the customer to accept the mismatched item at the low offer price

4. **On successful sale**:
   - Add `offer_value` to both `scrap` and `score`
   - Increment `faction_sales[faction_id]` counter
   - Adjust `standing[faction_id]` by +1 (or more for strong matches)
   - Record transcript event
   - Delete ShedItem
   - Activity row deleted, `pending_activity_id` cleared

5. **On failed/abandoned negotiation**:
   - Artifact returns to Shed unchanged
   - No scrap or score
   - Activity row deleted, `pending_activity_id` cleared
   - AP is still consumed

**Invariants**:
- Selling skill level affects negotiation outcomes (see 6.6)
- Offers are generated fresh per customer interaction — never persisted across
  visits
- Customers do not remember previous offers or visits
- At most ONE customer per Market Visit

### 6.6 Skills (Mechanical Effects — TODO)

Detailed skill effects are implementation-defined. This section outlines the
intent for each skill category. Exact parameters will be tuned during
development.

**Prospecting (levels 1–3)**:
- Intended effect: Bias artifact draw toward higher-value or more desirable
  artifacts; may increase base_value range or weight selection.
- Does NOT affect push/collapse math directly.

**Upcycling (levels 1–3)**:
- Intended effect: Improve value gain per push, reduce instability growth per
  push, or increase evolution chance. Makes pushing more efficient without
  removing collapse risk.

**Selling (levels 1–3)**:
- Intended effect: Improve estimated value accuracy, reduce customer irritation
  gain, increase settle_chance, improve offer multiplier on matching artifacts.
  May reveal one desired behavior to the player.

Skill costs are defined in `content/skills.yml`. Cost scales per level (e.g.
level 1 costs 10 scrap, level 2 costs 25, level 3 costs 50). Skill training
does not cost AP.

### 6.7 Market Dynamics — Planned

Future refinement beyond MVP:
- Similar artifacts sold repeatedly depress price for that trait
- Factions have daily appetite caps
- Rival sales affect supply and price
- Late-season market saturation prevents optimal last-day dumping
- Some days favor or punish certain artifact types

#### Catch-Up Through Faction Rivalry

When a faction trails significantly in aggregate influence, random events
can offer premium standing gains or bonus scrap for selling to them.
Narrative: the underdog faction recruits players as counter-agents against
the dominant faction. This provides soft rubber-banding without altering
artifact physics or directly penalizing the leader.

Implementation sketch: the daily maintenance timer checks faction influence
ratios; if the gap exceeds a threshold, a "Desperate Recruiter" flag is set
for the trailing faction. MarketVisit activity checks this flag and applies
bonuses (extra standing, higher multiplier) when the player sells to that
faction. The event is gated behind `faction_sales[faction_id] >= 1` so only
players who have already engaged that faction can trigger it.

These are not required for the initial implementation.

---

## 7. Faction System

### 7.1 Factions (content-driven, loaded from YAML config)

| ID | Name | Interests | Base Multiplier | Disposition |
|----|------|-----------|-----------------|-------------|
| syndicate | The Syndicate | thermal, storage, food_processing, power | 1.1 | commercial_resale |
| libremount | LibreMount | thermal, water, sanitation, medical_response, power | 0.9 | public_distribution |
| faculty | The Faculty | signal, revelation, field, medical_response | 1.0 | scholarly |
| purifiers | The Purifiers | force, instability, medical_response | 1.2 | destruction |
| revelationists | The Revelationists | revelation, signal, field, transformation | 0.8 | sacred_custody |

Faculty has a special rule: its `effective_multiplier` increases for evolved
(breakthrough) artifacts.

Factions are defined as configuration data, NOT as class hierarchies. A
FactionRegistry loads the YAML definition. Subclass behavior is only justified
when a faction has structurally unique mechanics (e.g., Faculty's evolved
artifact premium).

### 7.2 Three-Layer Faction Model

Factions have three connected layers:

**Personal Standing** ("What do they think of me?"):
- Per-character integer per faction
- Increased by selling to them (especially high-value or matching artifacts)
- Affects: customer frequency, prices, commissions, special text, faction access
- Stored in `character.standing` map

**Faction Influence** ("How powerful is this faction this season?"):
- Aggregate of all sales to this faction across all players
- Affects: Crier reports, customer mix, Bazaar conditions, rival behavior
- Stored in `season.faction_state` (influence value)

**Artifact Intake** ("What kinds of artifacts did this faction receive?"):
- Tracks artifact traits received by faction
- Affects: narrative events, faction behavior shifts, Crier reports
- Stored in `season.faction_state.intake_by_trait` map

### 7.3 Commission System — Planned

After a player's second seasonal sale to a faction, that faction "notices" the
player and may issue a commission:

- **Trigger**: `faction_sales[faction_id] >= 2` AND no active commission AND
  faction not already `noticed`
- **Effect**: Sets `noticed[faction_id] = true`
- **Commission shape**:
  ```
  {
    "faction_id": "faculty",
    "behaviors": ["signal", "revelation"],
    "remaining_attempts": 3,
    "premium_multiplier": 1.5,
    "trigger_text": "..."
  }
  ```
- **Premium application**: When selling a matching artifact to this faction
  during a Market Visit, multiply offer value by `premium_multiplier`.
- **Fulfillment**: Selling a matching artifact to the commission faction while
  a matching commission is active fulfills it — `active_commission` is cleared.
- **Expiry**: Decrements `remaining_attempts` each time the player starts a
  new prospecting attempt. At 0, the commission expires.
- **Constraints**: At most ONE active commission. No quest-acceptance UI
  required. Player may always ignore the commission.

---

## 8. Daily Maintenance & Season Lifecycle

### 8.1 Daily Maintenance (In-Process Timer)

Maintenance is managed by `MagicMountain::Maintenance`, driven by a
`Mojo::IOLoop->recurring(60 => ...)` timer that fires every 60 seconds.
When the configured `end_of_day_hour` arrives, the maintenance window
executes.

**Configuration** (in `magic_mountain.yml`):
```yaml
end_of_day_hour: 0              # 0–23, local time hour when maintenance fires
maintenance_window_minutes: 5   # planned gate duration (route guard fires
                                # for the duration of the callback)
```

**Maintenance.pm lifecycle**:

1. Every 60 seconds, `dailyMaintenance()` is called.
2. If current time has not reached `next_run`, it returns immediately (no-op).
3. If `next_run` has arrived:
   a. Sets `in_maintenance` flag to `true` (write routes return HTTP 503).
   b. Advances `next_run` to the same hour on the following day.
   c. Invokes the `on_maintenance` callback.
   d. Clears `in_maintenance` flag after callback completes.

**`on_maintenance` callback** (day-rollover logic):

This callback is the single place where day-advancement logic lives. It
receives the Maintenance object (`$self`). Implementation:

1. Increment `season.day` by 1
2. For every SeasonalCharacter: reset `action_points` to `action_points_max`
3. Apply artifact decay to every ShedItem (see 6.4)
4. Preserve activity rows — in-progress prospecting survives rollover
5. Update leaderboard snapshots
6. If `season.day > season_length`, emit a warning (season end is manual)

**Route gating during maintenance**:

Routes are partitioned into three tiers via Mojolicious `under` bridges:

| Tier | Routes | During Maintenance |
|------|--------|--------------------|
| Public read-only | `GET /`, `/login`, `/logout`, `DELETE /sessions` | Allowed |
| Writes (no auth) | `POST /sessions` | HTTP 503 |
| Authenticated | `GET /player`, `DELETE /player`, `GET /game`, all game action endpoints | HTTP 503 |

The `is_maintenance` helper checks `$app->maintenance->in_maintenance` and
returns 503 for gated routes.

**Invariants**:
- Controllers NEVER check for or apply daily rollover
- Controllers trust `action_points` as written by the maintenance callback
- The `in_maintenance` flag blocks concurrent writes during the callback
- Login and account creation are rejected during maintenance (503)

### 8.2 Season Start

Admin-triggered. Creates a new Season record with status `active`, day 1.
Season length is a game constant (e.g., 30 days). When a player joins
mid-season, their character is created with full AP at the current season day.

### 8.3 Season End (Finalization)

Admin-triggered. MUST execute in this exact order:

1. Compute final leaderboard rank for each character
2. For each SeasonalCharacter:
   a. Collect final stats (score, scrap, standing, faction_sales, skills)
   b. Collect significant ArtifactDisposition records
   c. Build SeasonRecord (score, scrap, rank, standing snapshot, skills
      snapshot, disposition summaries, narrative hooks)
   d. Store SeasonRecord (append-only, survives deletion)
3. Verify ALL SeasonRecords are stored successfully
4. Discard all ShedItems for this season
5. Delete ALL SeasonalCharacter rows for this season
6. Clear SeasonFactionState
7. Set Season.status = "archived"

Hard-deletion of characters is ONLY permitted after this formal sequence.
Pending activities are discarded at season end — unresolved artifacts are
forfeit. Shed items are forfeit (not carried to next season).

---

## 9. Activity System

Every expedition (Prospecting, MarketVisit) is a state machine and a persisted
entity. Activity extends `MagicMountain::Model` — the same JSON-file CRUD base
as Account, Character, and Season. Activity state lives in `activities.json`,
linked to characters via `pending_activity_id`.

### 9.1 Activity Base Class

`MagicMountain::Activity` provides the persistence layer, state-machine skeleton,
content loading, and column accessors. Subclasses declare their legal transitions
and implement handler methods.

**Two categories of fields on the same object:**

| Category | Mechanism | Examples |
|----------|-----------|----------|
| Persisted | Declared in `columns`, accessed via `getCol`/`setCol`, survives `save()` | `char_id`, `type`, `phase`, `artifact`, `customer` |
| Ephemeral | Regular Mojo `has` attributes, set at construction, shared across instances | `transitions`, `app`, `content_filename`, `content_data`, `log` |

**Column accessors:** `phase`, `artifact`, and `customer` have convenience
accessor methods that bridge Mojo attribute syntax (`$self->phase('processing')`)
to column storage (`getCol`/`setCol` — reading/writing `$self->row`).

**Construction overrides:** The base class overrides `get()` and `create()` from
Model. After calling `SUPER` (Model's versions which pass `file`/`log`/`table`/`row`
to `new()`), they propagate ephemeral attributes (`transitions`, `app`, `content_data`)
from the global instance to the new instance.

**Dispatch:**

```perl
sub dispatch ($self, $char, $action, %params) {
    die "illegal transition: " . ($self->phase // 'undef') . " -> $action"
        unless grep { $_ eq $action } @{ $self->transitions->{$self->phase} // [] };
    die "no handler for action: $action"
        unless $self->can($action);

    return $self->$action($char, %params);
}
```

The base class reads `$self->phase` — a column accessor, NOT the character's
data. It validates the transition, checks the handler exists, and delegates.
Handlers set phase directly: `$self->phase('processing')`. No `next_phase`
return value. No `serialize()` / `from_serialized()` ceremony.

**Content loading:**

```perl
sub load_content ($self) {
    return if $self->content_data;
    return unless $self->content_filename;
    $self->content_data(LoadFile($self->content_filename));
}
```

`content_filename` is the full path to a single YAML file, set by the app class
at construction time. `content_data` holds the parsed result, propagated to new
instances by the overridden `get()`/`create()`. The base class handles YAML I/O;
subclasses interpret `content_data` in their own domain-specific way.

### 9.2 Subclass Contract

A subclass must:
1. Declare `has transitions => sub { { idle => [...], ... } }`
2. Override `create()` to set type/phase column defaults, then chain to `SUPER`
3. Implement one handler method per action in the transition table
4. Each handler receives `($self, $char, %params)`
5. Mutate character fields via `setCol` (e.g. `$char->setCol('scrap', $char->getCol('scrap') + $value)`)
6. Set phase directly: `$self->phase('processing')`
7. Persist activity row: `$self->save` (or on terminal outcomes: `$self->delete`.
   Also call `$char->save` — handlers own all persistence)
8. Return `{ view => {...} }` — the controller pipes `view` directly to the template

```perl
{
    view => {
        ok     => 1,
        result => 'push',
        artifact => { stage => 'strained', signal => 'It groans...', value => 24 },
        player   => { action_points => 13, scrap => 10, score => 10 },
    },
}
```

`instability`, `evolution_chance`, and other internal math must never appear in `view`.

### 9.3 Persistence Topology

```
characters.json                    activities.json
┌────────────────────┐             ┌─────────────────────────┐
│ id: "abc"          │             │ id: "xyz"               │
│ display_name: "J"  │──────FK────→│ char_id: "abc"          │
│ score: 42          │             │ type: "prospecting"     │
│ pending_activity_id│             │ phase: "processing"     │
│ action_points: 15  │             │ artifact: {...}         │
└────────────────────┘             └─────────────────────────┘

  │
  │ owns
  ▼
shed.json                          skills.yml                   
┌────────────────────┐            (content, not persistence)
│ char_id: "abc"     │
│ artifact_id: "..." │
│ condition: "fresh" │
│ decayed_value: 24  │
└────────────────────┘
```

### 9.4 Global Instance as Factory

One global instance per activity type (e.g. `$app->prospecting`), constructed
at startup, holding:
- `file` — path to `activities.json` (the persistence table)
- `content_data` — parsed YAML specs, loaded once via `load_content`
- `transitions`, `app`, `log` — shared ephemeral state

Per-request activity rows are created or loaded via the standard Model API:

```perl
# Idle character — create a new activity row
$activity = $app->prospecting->create(char_id => $char->getCol('id'));

# Active character — load existing row
$activity = $app->prospecting->get($char->getCol('pending_activity_id'));
```

Both return fully-functional instances with persisted columns and propagated
ephemeral attributes.

### 9.5 Prospecting Activity

```perl
# In MagicMountain.pm startup:
has prospecting => sub ($self) {
    MagicMountain::Activity::Prospecting->new(
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/prospecting.yml',
        log              => $self->log,
    )->load_content;
};

# Prospecting subclass:
has transitions => sub {
    { idle => ['begin'], processing => ['push', 'stop'] }
};

sub create ($self, %params) {
    $params{type}  //= 'prospecting';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}
```

**Prospecting flow**:

| Phase | Action | Effect | Persistence |
|-------|--------|--------|-------------|
| idle | begin | Deduct 2 AP. Draw artifact. Set phase to `processing`. Set FK | `$self->save`, `$char->save` |
| processing | push | Destabilize. May collapse, breakthrough, or normal (update artifact) | Collapse/breakthrough: `$self->delete`, clear FK, `$char->save`. Normal: `$self->save`, `$char->save` |
| processing | stop | Calculate estimate. Create ShedItem. Set phase to `idle` | `$item->save`, `$self->delete`, clear FK, `$char->save` |

The `awaiting_buyer` phase and `offers` column have been removed. Prospecting
no longer handles selling. Activities own all persistence — the controller
never calls `save` or `delete`.

### 9.6 MarketVisit Activity

```perl
has market => sub ($self) {
    MagicMountain::Activity::MarketVisit->new(
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/factions.yml',
        log              => $self->log,
    )->load_content;
};

# MarketVisit subclass:
has transitions => sub {
    { idle => ['begin'], negotiating => ['offer', 'send_away'] }
};

sub create ($self, %params) {
    $params{type}  //= 'market_visit';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}
```

**MarketVisit flow**:

| Phase | Action | Effect | Persistence |
|-------|--------|--------|-------------|
| idle | begin | Deduct 1 AP. Generate customer. Set FK. Set phase to `negotiating` | `$self->save`, `$char->save` |
| negotiating | offer | Receive `shed_item_id`. Match `desired_behaviors` vs item `behaviors`. Match → sale. Mismatch → no sale (customer leaves) | Match: `$self->delete`, `$char->save`. Mismatch: `$self->delete`, `$char->save` |
| negotiating | send_away | Player ends negotiation. No sale. | `$self->delete`, `$char->save` |

The `offer` action takes a `shed_item_id` parameter identifying which artifact
from the player's shed is being offered. Irritation, counter-offers, settle
rolls, and showing multiple items per visit are planned enhancements.

### 9.7 Bots

Bots call the same `dispatch()` method with the same character model.
The transition table is checked identically — a bot cannot exploit HTTP
endpoint knowledge because the state machine lives in the activity, not
in the route.

Bots use the same Shed and Market systems. Their inventory is stored alongside
human players' in `shed.json`. Bot policies must be updated to handle the
prospecting → shed → market visit flow (see section 14).

---

## 10. Request Handling (Controllers)

Controllers are thin adapters between HTTP and the activity system.
They handle one specific game action each and contain no game logic.

### 10.1 Controller Structure

Each controller action follows this pattern:

```perl
sub action_name ($self) {
    my $player_id = $self->current_player;

    my ($char_model) = @{ $self->app->characters->find(
        sub ($row) { $row->{account_id} eq $player_id }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $p   = $self->app->prospecting;       # or $self->app->market
    my $id  = $char_model->getCol('pending_activity_id');

    my $activity = $id
        ? $p->get($id)
        : $p->create(char_id => $char_model->getCol('id'));

    my $result = $activity->dispatch($char_model, $action, %params);

    $self->render(json => $result->{view});
}
```

The controller loads or creates the activity row, dispatches, and renders.
The activity handler owns all persistence — character saves, activity saves and
deletes, shed item creation. The controller never calls `save` or `delete` on
any model.

### 10.2 Controller Inventory

| Controller | Actions | Purpose |
|-----------|---------|---------|
| Root | index | Gateway redirect (/ → /login or /game) |
| Sessions | login_form, create, destroy, logout | Authentication |
| Player | show, destroy | Current player JSON; delete account |
| Game | show | Game state page |
| Prospecting | begin, push, stop | Prospecting lifecycle |
| Market | begin, offer, send_away | Market negotiation lifecycle |
| Shed | index | List shed contents with condition and estimates |
| Skills | index, purchase | View available skills, purchase upgrade |
| Leaderboard | index | Player rankings |

The old `Artifact` controller is renamed to `Prospecting`. The old `Sale`
controller is removed (replaced by `Market`). New `Shed` and `Skills`
controllers are added for inventory management and skill purchases.

### 10.3 What Controllers Do NOT Do

- Do NOT check for or apply daily rollover
- Do NOT advance the season clock or refresh AP
- Do NOT construct characters (created by join-season flow or maintenance)
- Do NOT create accounts (that's Sessions)
- Do NOT validate activity phases (the activity base class does this)
- Do NOT call persistence methods on models (the activity does this)
- Do NOT apply skill effects or decay (activities and maintenance handle this)
- Do NOT generate customers or match artifacts (Market activity handles this)
- Do NOT record transcript events (the activity and app class handle this)
- Do NOT inspect or filter the activity's view hashref — pipe it verbatim

---

## 11. Account & Login Flow

1. Client submits display name to login endpoint (`POST /sessions`)
2. `Model::Account` looks up name; if not found, creates a new record
   (UUID + username + timestamp) — accounts are auto-created on first login
3. A server-side session record is persisted (player_id, last_active) with
   configurable inactivity timeout (default 60 minutes, set via
   `session_timeout_minutes` in `magic_mountain.yml`)
4. Mojolicious session cookie stores `playerId`
5. When a player first accesses the game, a SeasonalCharacter is created for
   them (either by the join-season flow or the next maintenance cycle)
6. Controllers access character data via `Model::Character` — no intermediate
   coordinator

Display names must be unique.

### 11.1 Session Lifecycle

- **Login** (`POST /sessions`): Creates or reuses a persistent session
  record with `last_active` timestamp. Returns player info as JSON.
- **Touch**: The `current_player` helper validates the session on each
  authenticated request, updates `last_active`, and enforces the inactivity
  timeout. Expired sessions are cleaned up lazily on next access.
- **Logout (API)**: `DELETE /sessions` — destroys session record and
  expires the cookie. Returns JSON.
- **Logout (browser)**: `GET /logout` — same as above, then redirects
  to `/login`.
- **Current player**: `GET /player` — returns current player info if logged
  in, 401 if not.
- **Login form**: `GET /login` — renders the session creation form.
- **Root gateway**: `GET /` — redirects to `/login` (unauthenticated) or
  `/game` (authenticated).

---

## 12. Content System (YAML-Driven)

### 12.1 Directory Structure

```
content/
  prospecting.yml                 # All artifact definitions
  skills.yml                      # Skill definitions and costs
  factions.yml                    # Faction definitions (future: expanded traits)
  text/
    daily_messages.yml
    season_opening.yml
    customer_offers.yml           (future)
    commission_triggers.yml       (future)
    negotiation_reactions.yml     (future)
```

### 12.2 Artifact Definition Shape

Each YAML file contains an array of artifact definitions:

```yaml
- id: thermal_box_001           # Unique identifier
  archetypes: [energy]           # Thematic grouping (unused mechanically)
  behaviors: [thermal]           # Tags used for faction interest matching
  weight: 10                     # Relative probability of being drawn
  base_value: 5                  # Starting sale value
  starting_instability: 0        # Always 0
  max_instability: 14            # Upper bound for ratio calculation
  instability_growth_min: 1      # Min instability added per push
  instability_growth_max: 2      # Max instability added per push
  base_gain_min: 3               # Min value gained per push
  base_gain_max: 5               # Max value gained per push
  can_evolve: true               # Can this artifact breakthrough?
  evolution_threshold: 0.25      # Min instability ratio for evolution check
  evolution_chance: 0.03         # Probability of breakthrough per push
  evolution_instability_spike: 2 # Extra instability added on breakthrough
  breakthrough_multiplier_min: 1.5  # Min value multiplier on breakthrough
  breakthrough_multiplier_max: 2.0  # Max value multiplier on breakthrough
  state_thresholds:              # Ratio boundaries for stage text
    stable: 0.35
    strained: 0.70
  decay_modifiers:               # How decay affects this artifact type
    fresh_multiplier: 1.0
    settling_multiplier: 0.75
    fading_multiplier: 0.4
    settling_day: 2
    fading_day: 5
  intro: >-                      # Text shown when artifact is first drawn
    The box is warm to the touch...
  signals:                       # Arrays of flavor text per stage
    stable:
      - A comfortable warmth radiates...
      - ... (at least 10 per stage)
    strained:
      - The box grows uncomfortably hot...
      - ...
    unstable:
      - The metal creaks and pulses...
      - ...
  collapse:                      # Array of collapse descriptions
    - It splits open with a hiss...
```

The `decay_modifiers` section is new — it defines how this artifact type
responds to decay. If omitted, default values apply.

### 12.3 Skill Definition Shape

```yaml
skills:
  - id: prospecting
    name: Prospecting
    description: "Find better artifacts and richer yields"
    max_level: 3
    levels:
      - level: 1
        cost: 10
        description: "Better leads"
      - level: 2
        cost: 25
        description: "Richer veins"
      - level: 3
        cost: 50
        description: "Eye for the unusual"
  - id: upcycling
    name: Upcycling
    description: "Push artifacts further with greater control"
    max_level: 3
    levels:
      - level: 1
        cost: 10
        description: "Firm touch"
      - level: 2
        cost: 25
        description: "Steady hand"
      - level: 3
        cost: 50
        description: "Master's feel"
  - id: selling
    name: Selling
    description: "Read customers and close better deals"
    max_level: 3
    levels:
      - level: 1
        cost: 10
        description: "Better haggling"
      - level: 2
        cost: 25
        description: "Customer reader"
      - level: 3
        cost: 50
        description: "Dealmaker"
```

### 12.4 Text Content Shape

**daily_messages.yml**: Array under `daily_messages` key. Shown on state
requests, cycled by season day or random.

**season_opening.yml**: Array under `season_opening` key. Shown on day 1
of each season.

**customer_offers.yml** (future): Per-faction customer offer text, tiered
by match quality.

**commission_triggers.yml** (future): Per-faction commission definitions
(behaviors, premium_multiplier, trigger_text).

### 12.5 Content Loading

The app class sets `content_filename` to the full path of the activity's YAML
file. `load_content` is called once at startup on the global instance. The
parsed data is stored in `content_data` and automatically propagated to
per-request activity instances via the overridden `get()`/`create()` methods.

Skill definitions are loaded by `Model::Skill` from `content/skills.yml` and
made available to the Skills controller and Model::Character.

Adding a new artifact requires editing `content/prospecting.yml` — no code
changes, no manual registration.

---

## 13. API Endpoints

### 13.1 Endpoint Table

| Method | Path | Controller#Action | Purpose |
|--------|------|-------------------|---------|
| GET | `/` | `Root#index` | Gateway redirect |
| GET | `/login` | `Sessions#login_form` | Login form |
| POST | `/sessions` | `Sessions#create` | Login or auto-create player |
| DELETE | `/sessions` | `Sessions#destroy` | Logout (API, JSON) |
| GET | `/logout` | `Sessions#logout` | Logout (browser, redirects) |
| GET | `/player` | `Player#show` | Current player JSON |
| DELETE | `/player` | `Player#destroy` | Delete account |
| GET | `/game` | `Game#show` | Game state page |
| POST | `/prospecting/begin` | `Prospecting#begin` | Start prospecting (costs 2 AP) |
| POST | `/prospecting/push` | `Prospecting#push` | Destabilize artifact |
| POST | `/prospecting/stop` | `Prospecting#stop` | Halt, create shed entry |
| POST | `/market/begin` | `Market#begin` | Start market visit (costs 1 AP) |
| POST | `/market/offer` | `Market#offer` | Offer shed item to customer |
| POST | `/market/send_away` | `Market#send_away` | End negotiation, no sale |
| GET | `/shed` | `Shed#index` | List shed contents |
| GET | `/skills` | `Skills#index` | List available skills and current levels |
| POST | `/skills/purchase` | `Skills#purchase` | Buy skill upgrade (costs scrap) |
| GET | `/leaderboard` | `Leaderboard#index` | Player rankings |

### 13.2 Controller Action Contracts

**Prospecting#begin**: Requires `action_points >= 2` and no active activity
(`pending_activity_id` null). Deducts 2 AP. Draws random artifact from Content
pool. Creates a new activity row with phase `processing`.

**Prospecting#push**: Requires activity `type == "prospecting"` and
`phase == "processing"`. Delegates to `Activity::Prospecting::push()`.
Possible outcomes: normal (updated artifact), collapse (row deleted),
breakthrough (cashed out, row deleted).

**Prospecting#stop**: Requires activity `phase == "processing"`. Creates
ShedItem with estimated value range. Deletes activity row. Returns shed item
summary to client.

**Market#begin**: Requires `action_points >= 1` and no active activity.
Deducts 1 AP. Generates customer. Creates activity row with phase
`negotiating`. Returns customer info (faction name, disposition — NOT
desired_behaviors).

**Market#offer**: Requires activity `type == "market_visit"` and
`phase == "negotiating"`. Receives `shed_item_id` in request body.
Runs negotiation logic. May result in sale (scrap+score, shed item deleted,
activity deleted) or continued negotiation (irritation updated, activity
saved).

**Market#send_away**: Requires activity `phase == "negotiating"`. Ends
negotiation without sale. Artifact remains in shed. Activity row deleted.

**Shed#index**: No activity required. Returns all ShedItems for the character
with condition, estimated value range, artifact name, and age.

**Skills#index**: Returns skill definitions from YAML plus the character's
current skill levels.

**Skills#purchase**: Receives `skill_id`. Validates character has enough scrap
and current level < max_level. Deducts scrap. Increments skill level on
character.

### 13.3 Response Shape for Game State

```json
{
  "ok": true,
  "player": {
    "name": "Joe",
    "action_points": 13,
    "action_points_max": 15,
    "scrap": 42,
    "score": 42,
    "faction_sales": { "syndicate": 2, "libremount": 1 },
    "skills": { "prospecting": 1, "upcycling": 0, "selling": 2 }
  },
  "prospecting": {
    "id": "thermal_box_001",
    "stage": "strained",
    "value": 18,
    "signal": "The box grows uncomfortably hot...",
    "intro": "The box is warm to the touch..."
  },
  "market_visit": {
    "customer": {
      "faction_id": "syndicate",
      "faction_name": "The Syndicate",
      "disposition": "commercial_resale"
    },
    "irritation": 0
  },
  "shed": [
    {
      "id": "<uuid>",
      "artifact_id": "thermal_box_001",
      "condition": "fresh",
      "estimated_value_min": 14,
      "estimated_value_max": 22,
      "days_in_shed": 0
    }
  ],
  "season": { "day": 5, "total_days": 30 },
  "world_message": "The air tastes faintly of ozone...",
  "season_opening": null
}
```

`prospecting` is present only when the active activity is type `prospecting`.
`market_visit` is present only when the active activity is type `market_visit`.
`shed` is always present when idle (listing all owned artifacts).
Both `prospecting` and `market_visit` are null when idle.

---

## 14. Bot Simulation

Bots are automated players that invoke the same service classes as the web
controllers. The simulate CLI command reads artifact content, iterates through
a population of bots, and calls `Activity::Prospecting`, `Activity::MarketVisit`,
`Shed`, and `SeasonalCharacter` mutators directly — producing game outcomes
identical to human play.

### 14.1 Push Policies

| Policy | Parameters | Behavior |
|--------|------------|----------|
| `fixed_pushes` | `max` (default 3) | Push exactly N times, then stop |
| `instability_cap` | `max` (default 5) | Push until instability exceeds cap |
| `stage_guard` | `stop_at` (default "unstable") | Push until target stage reached |
| `greed` | `prob` (default 0.7) | Push with probability P each time |
| `value_target` | `min` (default 20) | Push until value exceeds target |
| `composite` | `op` ("and"/"or"), `policies` (sub-policy array) | Combine multiple policies |

### 14.2 Selling Policies

| Policy | Behavior |
|--------|----------|
| `highest_offer` | Accept any offer above a value threshold |
| `faction_loyalist` | Sell only to specific faction, pass on others |
| `opportunist` | Accept any match, pass on mismatches |
| `desperate` | Accept any offer including mismatches at low value |
| `hoarder` | Skip market visits, accumulate shed items |

### 14.3 Bot Strategy Profile

A bot profile combines a push policy with a selling policy:

```yaml
- id: alice
  display_name: "Alice"
  push_policy: { name: "stage_guard", params: { stop_at: "unstable" } }
  sell_policy: { name: "opportunist" }
  skill_profile: { prospecting: 1, upcycling: 2, selling: 0 }
```

Bot profiles are defined in YAML content (future: `content/bots.yml`).

---

## 15. Transcript

JSONL (JSON Lines) file for recording game events. Each event is one JSON
object per line with a `narrative` field for human/LLM readability. Used for
simulation analysis, balance evaluation, and diagnostics. Events include:
`artifact_start`, `push`, `collapse`, `breakthrough`, `stop`, `shed_entry`,
`market_visit`, `offer`, `sale`, `sim_start`, `sim_end`, and future
`commission_triggered`, `commission_fulfilled`, `commission_expired`.

**Transcript lifecycle**: The app class opens a transcript context on each
request, capturing session, player, endpoint, and timestamp. Activities
enrich the transcript with game events during their execution. The app
class closes the transcript with duration and outcome after the response
is rendered. No single module is the sole transcript writer — the app,
activities, and future diagnostics all contribute to the same event stream.

---

## 16. Narrative Constraints

These are non-negotiable rules for all content:

- **Player role**: The player is purely opportunistic — never a savior, never
  a villain. The game does not morally categorize the player.

- **Tone**: Grounded and observational. All characters must genuinely believe
  their actions make sense. The world should feel lived-in, not epic.

- **Presentation**: Favor implication and suggestion over outright explanation.
  Show danger ("The core screams") rather than tell danger ("The core is
  unstable"). Use concrete sensory detail.

- **Scope**: Violence and combat are not depicted. Conflict is economic,
  political, and environmental. Artifact collapse is mechanical failure, not
  human harm. PvP is economic interference, not direct harm.

---

## 17. Architecture Invariants (Do Not Violate)

### Persistence

1. **Models own their own persistence.** `Model::Character`, `Model::Account`,
   `Model::ShedItem`, etc. provide `save()`, `create()`, `find()`. No separate
   State or persistence coordinator layer wraps them.

2. **Models must not contain game logic.** A model's columns and CRUD
   operations are pure data access. Artifact math, decay, negotiation rules,
   and transition validation live in activities and services.

### Activities

3. **Activities are persisted entities, not transient services.** They extend
   `MagicMountain::Model` and store state in `activities.json`. Phase, artifact,
   and customer are persisted columns. Transitions, app, content_data, and
   log are ephemeral attributes propagated from the global instance.

4. **The activity base class enforces state-machine transitions.** Every
   dispatch checks the transition table before delegating to the subclass.
   Neither the controller nor the subclass performs phase validation.

5. **Activities define the view contract.** The `view` hashref they return
   is piped directly to the template. Activities decide what is
   player-visible; controllers do not inspect or filter.

6. **Activities receive a character model as a parameter to `dispatch()`.**
   The global instance is constructed with `file`, `app`, `content_filename`,
   and `log`. Context data (character state, user input) arrives per-call.

### Market & Negotiation

7. **MarketVisit generates customers only.** It never directly modifies the
   Shed or character. Negotiation is handled by the MarketVisit activity,
   which calls Shed methods to remove sold items and Character methods to
   award scrap/score.

8. **Once a negotiation ends, offers are not preserved.** The customer and
   their offers are ephemeral. No offer survives across market visits.

### Action Points & Rollover

9. **Prospecting costs 2 AP. Market visits cost 1 AP.** These costs are
   deducted at `begin` time and are non-refundable.

10. **Only the on_maintenance callback advances the season clock, refreshes
    AP, or applies decay.** Controllers never check for or apply daily
    rollover.

11. **Active activity rows survive day rollover** and are discarded only at
    season finalization.

### Characters & Deletion

12. **Seasonal characters may be deleted only after** final SeasonRecord
    creation succeeds. ShedItems are forfeit at season end.

### Gameplay Invariants

13. **Faction standing and influence must not alter artifact push/collapse
    physics.** Market offers may vary, but artifact behavior does not.

14. **Score is cumulative sale value and never decreases.**
    Scrap is spendable seasonal currency that may decrease through skill
    purchases. Score is NOT reduced by scrap expenditure.

15. **Collapse = zero salvage.** No partial recovery. This is the game's core
    risk.

16. **At most one evolution per artifact.** `has_evolved` flag prevents
    re-triggering.

### Accounts & Sessions

17. **Display names must be unique.** Login creates accounts; controllers
    never do.

18. **Session timeout is configurable and enforced server-side.** Model::Session
    tracks `last_active` per player. Expired sessions are cleaned up lazily.

### Content & Factions

19. **Faction definitions are data, not code.** FactionRegistry loads YAML.
    Subclass behavior is an exception, not the pattern.

20. **Narrative emissions are not activities.** They do not consume action
    points.

### Transcript

21. **The app class owns transcript lifecycle.** It opens a transcript context
    on each request (session, player, endpoint, timestamp). Activities enrich
    it with game events. The app closes it (duration, outcome). No single
    module is the sole transcript writer.

### Shed & Decay

22. **Shed items are forfeit at season end.** They are never carried over.

23. **Estimated values are ranges, not exact figures.** The player sees
    `estimated_value_min` and `estimated_value_max`, never the precise
    `decayed_value`.

24. **Decay never destroys artifacts.** Even `fading` artifacts can be sold.
    Value may approach zero but the artifact remains.

---

## 18. Activity Discovery (Dynamic Registration)

New activity types are discovered at startup by scanning the Activity
directory. Any class in that namespace is automatically loaded and registered
by its `name()` (lowercased short class name). Adding a new activity type is a
single-file operation — no manual registration, no wiring changes.

The activity registry lives on the app instance (`$app->activities`) and is
available to controllers at request time.

---

## 19. Implementation Status (New Codebase)

The new codebase (`lib/`) is a ground-up rebuild.

### 19.1 Implemented

| Feature | Module(s) | Notes |
|---------|-----------|-------|
| **Model persistence layer** | `Model.pm`, `Model::Account`, `Model::Character`, `Model::Season`, `Model::HallOfFame`, `Model::Session`, `Model::AuditLog` | JSON file CRUD, UUID, atomic write-via-temp-file |
| **Routing gateway** | `Controller::Root` | `GET /` redirect |
| **Login flow** | `Controller::Sessions` | Auto-creates accounts on first login |
| **Player info** | `Controller::Player` | `GET /player` JSON or 401 |
| **Game page** | `Controller::Game`, `templates/game/show.html.ep` | Authenticated home with season info |
| **Session management** | `Model::Session`, `current_player` helper | Configurable inactivity timeout |
| **CLI commands** | `Command::create_account`, `Command::list_accounts`, `Command::delete_account`, `Command::disable_account`, `Command::simulate` | Account lifecycle, bot simulation |
| **Layout** | `templates/layouts/default.html.ep` | Bootstrap 5.3 CDN wrapper |
| **Day maintenance** | `Maintenance.pm` | IOLoop timer, route gating, `on_maintenance` callback for AP refresh, day increment, decay |
| **Audit logging** | `Model::AuditLog` | JSONL login/logout/account events |
| **Activity base class** | `Activity.pm` | State-machine dispatch, column accessors, content loading |
| **Prospecting activity** | `Activity::Prospecting` | Push/collapse/breakthrough math, stop → shed entry, activity-owned persistence |
| **MarketVisit activity** | `Activity::MarketVisit`, `Controller::Market` | Customer generation, match-based selling, empty shed guard |
| **ShedItem model** | `Model::ShedItem` | `shed.json` CRUD, per-character queries |
| **Character invariants** | `Model.pm` validate hook, `Model::Character` override | AP bounds, scrap non-negative, score never decreases, skills 0–3 |
| **Character column expansion** | `Model::Character` | `action_points`, `action_points_max`, skill columns |
| **Prospecting/Market controllers** | `Controller::Prospecting`, `Controller::Market` | Thin dispatch+render, no persistence |
| **Content YAML** | `content/prospecting.yml`, `content/skills.yml`, `content/factions.yml` | Artifact definitions, skills, factions |
| **Transcript system** | `Model::Transcript` | JSONL event log with narrative, integrated into all activity handlers |
| **Bot simulation** | `Command::simulate`, `script/analyze` | Naive bot strategy, real game engine, reproducible, analysis script |

### 19.2 Needs Update (Existing Code to Refactor)

| Module | Change Required |
|--------|-----------------|
| `Controller/Game.pm` | Update game state response to include shed, skills, new AP fields |
| Skill mechanical effects (§6.6) | Implement per-level effects for prospecting, upcycling, selling |

### 19.3 Planned (Not Yet Implemented)

| Feature | Priority | Notes |
|---------|----------|-------|
| Shed/Skills/Leaderboard controllers | High | HTTP endpoints for inventory, skill purchase, rankings |
| Artifact decay (in maintenance) | High | Condition states, value recalculation |
| Skill system purchase flow | High | YAML-driven skill definitions, purchase endpoint |
| MarketVisit negotiation math | Medium | Irritation, settle rolls, counter-offers, multiple items per visit |
| Bot policy framework | Medium | Pluggable push/sell policies, YAML bot profiles |
| Faction system (FactionRegistry, YAML config) | Medium | Standing, influence, intake tracking |
| Commission system | Low | Faction notices, active commissions |
| Crier narrative system | Low | Faction/economic state driven reports |
| Market dynamics (supply/demand) | Low | Price depression, faction appetites |
| MariaDB migration | Future | Replace JSON file persistence |
| Faction system (FactionRegistry, YAML config) | Medium | Customer generation |
| SeasonFactionState tracking | Medium | Influence, intake tracking |
| ArtifactDisposition records | Medium | Append-only immutable sale records |
| Commission system | Low | Faction notices, active commissions |
| Transcript events | Low | JSONL for simulation and balance analysis |
| Leaderboard | Low | Player rankings |
| Crier narrative system | Low | Faction/economic state driven reports |
| Market dynamics (supply/demand) | Low | Price depression, faction appetites |
| MariaDB migration | Future | Replace JSON file persistence |

---

## 20. Key Design Decisions (Rationale Record)

1. **Two-phase architecture over central coordinator**: Player actions and
   daily maintenance are different concerns with different callers (HTTP vs
   IOLoop timer). Separating them eliminates an unnecessary dispatch layer
   and makes each phase simpler to test and reason about.

2. **Single activity row** over character-embedded blob: Activity state lives
   in its own `activities.json` table, linked via `pending_activity_id` FK. Only
   one activity can be in progress per character. When the phase returns to idle,
   the row is deleted.

3. **Activity extends Model**: Activity is a persisted entity with columns
   (phase, artifact) and ephemeral attributes (transitions, content_data).
   One global instance per activity type holds the persistence table and loaded
   content; per-request rows are created/loaded via Model's `get()`/`create()`.

4. **In-process maintenance timer over cron-triggered rollover**: A
   `Mojo::IOLoop` recurring timer drives the `Maintenance.pm` state machine.
   The `in_maintenance` flag gates write routes during the maintenance
   window, and the `on_maintenance` callback is the single extension point
   for all day-rollover logic (AP refresh, decay, day increment).

5. **Prospecting and selling are separate activities**: They are different
   mental modes with different AP costs. Prospecting is push-your-luck
   mechanical tension. Selling is social/economic negotiation. Separating them
   keeps both loops clean and allows each to be developed and balanced
   independently.

6. **Inventory (Shed) between prospecting and selling**: Artifacts enter the
   shed after prospecting and remain until sold or season end. This enables
   decay pressure, market timing decisions, and inventory strategy —
   the player must decide when to sell, not just sell immediately.

7. **Single action pool with weighted costs**: 15 AP/day shared across all
   activities. Prospecting costs 2 AP (heavier commitment). Market visits cost
   1 AP (lighter commitment). This lets players choose their daily mix rather
   than forcing a fixed split.

8. **Customer-first selling model**: The customer appears with hidden demand.
   The player offers from inventory. This creates good and bad market days,
   rewards Selling skill, and makes each market visit a unique negotiation
   rather than a menu pick.

9. **Offers never persist**: Customers and their offers are ephemeral per
   market visit. This prevents save-scumming and creates urgency. "Opportunity
   is not a lengthy visitor."

10. **Admin-triggered season end**: Never automatic. The maintenance callback
    may warn when configured season length is reached but does not
    auto-finalize.

11. **Collapse = zero salvage**: No partial recovery on collapse. This is the
    game's core risk; partial salvage would weaken the push-your-luck tension.

12. **At most one evolution per artifact**: `has_evolved` flag. No artifact
    can breakthrough more than once.

13. **Score vs Scrap separation**: Score is cumulative sale value (leaderboard
    metric, never decreases). Scrap is currency (spendable on skills). Score
    is NOT reduced by scrap expenditure — this encourages spending scrap on
    skills.

14. **Estimated values are ranges**: Players see `estimated_value_min` and
    `estimated_value_max`, never the precise internal `decayed_value`. This
    maintains uncertainty and makes Selling skill (which improves estimate
    accuracy) valuable.

15. **Three-layer faction model**: Personal standing (per player), faction
    influence (global per season), and artifact intake (what traits received).
    These layers connect economic activity to narrative without simulating
    everything.

16. **Commission premiums applied by activity, not customer generator**: The
    customer generator knows nothing about player state. The MarketVisit
    activity post-processes base offers to apply commission premiums.

17. **Decay applied during daily maintenance, not per-action**: All artifacts
    decay simultaneously at day rollover. This is predictable and avoids
    per-action overhead. The maintenance window is the natural sync point.

18. **Skills are YAML-driven, not hardcoded**: Skill definitions, costs, and
    descriptions in `content/skills.yml`. Adding or rebalancing a skill is a
    content edit, not a code change.

19. **SeasonalCharacter deletion after formal SeasonRecord creation**: The
    deletion is safe because the meaningful history has already been archived.

---

## 21. Open Design Questions (Implementation-Facing)

These questions remain unresolved and should be answered during implementation:

1. **Skill mechanical effects**: What does each level of Prospecting,
   Upcycling, and Selling actually do numerically? (See 6.6)
2. **Negotiation math**: Exact formulas for match bonus, irritation gain,
   settle probability, and offer values. (See 6.5)
3. **Customer generation**: How are customers selected from the faction pool?
   Weighted? Random? Standing-influenced?
4. **Action point count**: Is 15 the right default? Should `action_points_max`
   be configurable per season?
5. **Score display**: Should the game state show running score, or only the
   leaderboard? Score is visible until season end.
6. **Character-owned history name**: transcript, chronicle, ledger, or
   something else? (Refinements §21, item 4)
