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
  → Each day: 15–20 Action Points (AP, configurable via `default_action_points`, default 20)
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
| **Shed** (inventory manager) | ShedItem rows in `shed.json`, decay logic in `ShedManager.pm`, query/filter by traits | Market, Faction objects, Account model |
| **Market** (customer generator) | Faction objects, content reference, customer generation | Character model, Account model, Shed |
| **Model::Character** | File path, column definitions, JSON CRUD, invariant enforcement (AP bounds, scrap≥0, score never decreases, skills 0–3) | Market, Faction, Content, Shed, game math, artifact logic |
| **Model::ShedItem** | File path, column definitions, JSON CRUD | Game logic, decay math, faction rules |
| **Model::Account** | File path, column definitions, JSON CRUD | Game logic, season data, character data |
| **Model::Season** | File path, column definitions, JSON CRUD, finalize class method | Per-player character data, game logic |
| **Model::FactionSnapshot** | File path, column definitions, JSON CRUD | Game logic, character data |
| **Model::Session** | File path, column definitions, expiry logic | Game logic, character data |
| **Nav** (Controller::Nav) | App reference, fragment URL mapping, tab rules | Game logic, character data |
| **Skills** (YAML loader) | Directory path, parsed YAML data, app helper (`$c->skills_data`) | Game logic, character state |
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
| id | UUID | Primary key |
| username | string | Unique, user-chosen display name. Used as login credential. |
| password | string or null | Optional password hash. Currently null (name-only auth for alpha). |
| disabled | boolean | If true, account is locked (login rejected). Used for moderation. |
| createdAt | timestamp | Account creation time |

Survives across seasons. Contains no gameplay data.

### 5.2 Season (tournament)

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| label | string | Human-readable (e.g., "Season 1") |
| status | enum | upcoming / active / archived |
| day | integer | Current season day (starts at 1) |
| length | integer | Total days in this season |
| end_of_day_hour | integer | Hour (0–23) when maintenance fires for day rollover |
| faction_state | map | Per-faction influence, artifacts_received, intake_by_trait, and name |
| crier_message | string or null | Most recent Town Crier narrative text, generated during maintenance |
| crier_snapshot | map or null | Copy of faction_state from previous day, used for crier diffing |

### 5.3 Model::Character (one per player per season)

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| account_id | UUID | FK to PlayerAccount |
| season_id | UUID | FK to Season |
| name | string | Snapshot of name at season start |
| score | integer | Cumulative leaderboard value from sales. NEVER decreases |
| scrap | integer | Spendable currency. Decreases via skill purchases |
| action_points | integer | Current AP remaining for the day |
| action_points_max | integer | Daily AP cap (default 20, configurable via `default_action_points`) |
| faction_sales | map | Per-faction sale count this season |
| standing | map | Per-faction reputation integer |
| pending_activity_id | string or null | FK to activities.json row. null when idle |
| skill_prospecting | integer | 0–3, Prospecting skill level |
| skill_upcycling | integer | 0–3, Upcycling skill level |
| skill_selling | integer | 0–3, Selling skill level |
| current_location | string | Current location ID in the location graph (default: `camp`) |
| current_view | string | Last active view (idle/shed/factions/skills/account/market/prospecting). Managed by Nav controller — synced on every `/nav` response. Activity-only views invalidate when activity ends. |
| loyalty_visits_since | integer | Consecutive market visits without seeing the player's top faction. Used by loyalty access guarantee (see §6.5 step 1). |

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
| createdAt | timestamp | When the artifact entered the shed |
| updatedAt | timestamp | Last save time |
| decay_modifiers | map | Snapshot of artifact's decay_modifiers at stop time (fresh_multiplier, settling_multiplier, fading_multiplier, settling_day, fading_day) |

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

The `customer` column shape during negotiating includes market dynamics
state: faction_id, faction_name, desired_behaviors, base_multiplier
(the faction's static rate, before saturation/appetite/desperation adjustments
from §6.7 are applied). The effective multiplier is computed at offer time
by `_dynamic_multiplier()`.

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
  "evolution_instability_spike": 3,
  "breakthrough_multiplier_min": 1.5,
  "breakthrough_multiplier_max": 2.5,
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
  "irritation": 2,
  "irritation_threshold": 5,
  "settle_chance": 0.15,
  "offer_value": null,
  "offer_text": null,
  "soft_budget": 120,
  "absolute_budget": 144,
  "spent_so_far": 0,
  "loyalty_free_mismatches": 0
}
```

### 5.6 FactionSnapshot (daily faction history)

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| season_id | UUID | FK to Season |
| day | integer | Season day of this snapshot |
| faction_id | string | FK to faction definition |
| influence | integer | Accumulated value from all sales to this faction |
| artifacts_received | integer | Count of artifacts sold to this faction |
| intake_by_trait | map | Map of trait → count received |

One row per faction per day, written during daily maintenance (after Crier
message generation, before transcript logging) and on season finalization.
Append-only — never deleted. The last snapshot per faction (highest day) is
the authoritative final influence at season end.

---

### 5.7 SeasonFactionState (per-season live faction tracking)

| Field | Type | Description |
|-------|------|-------------|
| faction_id | string | FK to faction definition |
| season_id | UUID | FK to Season |
| influence | integer | Accumulated value from all sales to this faction |
| artifacts_received | integer | Count of artifacts sold to this faction |
| intake_by_trait | map | Map of trait → count received |
| daily_intake | integer | Artifacts bought today (reset each maintenance) |
| days_since_purchase | integer | Consecutive days without a sale to this faction |

Embedded in `season.faction_state` (§5.2). Updated atomically on every
sale and reset during daily maintenance. Used by market dynamics (§6.7)
for appetite and desperation calculation.

### 5.8 ArtifactDisposition (per-sale record)

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

Append-only. Immutable after creation. Survives character deletion. Created
during every successful sale (`_do_sale` in MarketVisit).

### 5.9 SeasonRecord (post-season archive)

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
| story_highlights | JSON | Notable dispositions, narrative hooks, and faction dominance summary (`top_faction`, `top_faction_influence`, `factions_competing`) |
| created_at | timestamp | When finalized |

Created during season finalization, before characters are deleted. Served to
players on first `/game` visit after the season ends as `season_recap`
(visible once, cleared on subsequent visits).

### 5.10 Skill Definition (content/skills.yml, loaded by `skills_data` helper)

Skills are defined in YAML content, not hardcoded:

```yaml
skills:
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

### 5.11 Entity Lifecycle

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
   - Default thresholds: `stable: 0.30`, `strained: 0.65` (set in `state_thresholds` per artifact spec)

4. **Collapse check**: `collapse_chance = (ratio³) × 0.95`
   - Clamped to maximum 100% (no minimum floor — near-zero ratio gives near-zero chance)
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
      - Instability increases by `evolution_instability_spike` (default 3)
      - Player receives `new_value` as both scrap and score
      - Activity row deleted (no stop needed, artifact never enters shed)
      - At most ONE evolution per artifact

6. **Value gain** (if no collapse and no breakthrough):
   - `gain = base_gain_min + random_int(0, base_gain_max - base_gain_min)`
   - `gain` is further increased by `upcycling_level - 1` when upcycling >= 2 (so +1 at level 2, +2 at level 3)
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

Decay is applied during daily maintenance. Managed by `MagicMountain::ShedManager`
which iterates all shed items and applies smooth daily value degradation.

**Per-artifact decay_modifiers**: Each artifact spec in `prospecting.yml`
optionally defines a `decay_modifiers` block:

```yaml
decay_modifiers:
  fresh_multiplier:     1.0
  settling_multiplier:  0.75
  fading_multiplier:    0.40
  settling_day:         2
  fading_day:           5
```

These modifiers are copied to the ShedItem at stop time (snapshotted, like
behaviors). If omitted, global defaults apply.

**Decay formula** (computed on each maintenance tick per item):

```
d = days_in_shed (incremented by 1 each tick)
mods = shed_item.decay_modifiers

if d < mods.settling_day:
    condition = 'fresh'
    mult      = mods.fresh_multiplier
elif d < mods.fading_day:
    condition = 'settling'
    progress  = (d - settling_day) / (fading_day - settling_day)
    mult      = fresh_multiplier + progress × (settling_multiplier - fresh_multiplier)
else:
    condition = 'fading'
    slope     = (settling_multiplier - fresh_multiplier) / (fading_day - settling_day)
    mult      = settling_multiplier + (d - fading_day) × slope
    mult      = max(mult, fading_multiplier)
```

`decayed_value = floor(original_value × mult)`

Estimated values are recalculated:
```
estimated_value_min = floor(decayed_value × 0.8)
estimated_value_max = floor(decayed_value × 1.2)
```

**Constraint**: `fading_day` must be strictly greater than `settling_day`.

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
   - `irritation` — starts at random 0–3 (varies per visit, press-your-luck from the outset)
   - `irritation_threshold` — if exceeded, customer leaves (default 5)
   - `settle_chance` — probability the customer will accept a non-matching item
   - `soft_budget` — 50–150 base + 5 per standing point with this faction
   - `absolute_budget` — 1.2 × soft_budget (hard cap)
   - `spent_so_far` — cumulative value of all purchases this visit (starts 0)

   Customer selection is standing-weighted: each faction's weight starts at 1.0
   and increases by +0.5 per point of personal standing with that faction. The
   higher a player's standing with a faction, the more likely its customers
   appear.

**Loyalty access guarantee**: If the player has 2+ sales to a single top
    faction and the rolled customer is from a different faction, a `loyalty_visits_since`
    counter tracks consecutive non-loyalty visits. After 3 such visits, the
    customer is forcibly redirected to the player's top faction (reset on
    any loyalty-faction visit). This ensures loyalists aren't starved of their
    preferred faction's customers.

    **Loyalty free mismatch**: If the player has 1+ prior sales to the visiting
    faction, the first mismatch each visit is free — no irritation is added.
    The `loyalty_free_mismatches` counter (initialized to 1 when
    `faction_sales >= 1`, 0 otherwise) is decremented on each mismatch.

2. **Player offer**: Player selects an artifact from their Shed and presents it
    to the customer. The negotiation logic:
     - If artifact behaviors intersect desired_behaviors:
       - **Match**: High offer at `floor(decayed_value × base_multiplier × match_mult)`.
         `match_mult` is 1.2 normally, 1.4 with Selling skill 3.
         Positive narrative response from `content/flavor/negotiation_reactions.yml`
         (per-faction flavor text, with `{item_id}` / `{value}` template variables).
         Falls back to generic text if no faction entry exists.
         Sale is automatic — no accept step.
     - If no intersection:
       - **Mismatch**: Low offer at `floor(decayed_value × base_multiplier × 0.5)`.
         Negative narrative response via `negotiation_reactions.yml`.
         A random roll against `settle_chance` (default 0.15) may cause the customer
         to accept the lowball anyway (see step 3).
         If the settle fails and **counter-offers are disabled**, irritation increases
         by exactly 1 (or 0 with Selling skill 2+), and the activity persists.
       - **Counter-offer (optional, gated by config)**: If `market_counter_offers`
         is enabled, the settle failure is followed by a customer counter at
         `floor(decayed_value × base_multiplier × counter_pct)`. `counter_pct`
         starts at 0.75, increased to 0.80 with Selling skill 2+, plus +0.01
         per point of standing with that faction (capped at 0.95). The player
          may accept (`accept_counter` action) or reject the counter (implicitly
          by offering a different item, which clears the pending counter and
          generates a fresh counter for the newly offered item; no irritation
          is added on counter rejection). The loyalty bonus does NOT apply to
          counter values.
     - After a result, the player may:
       - **Show another artifact**: Repeat offer step with a different shed item.
         Available after any non-storm-off outcome when the visit is still active.
       - **Accept counter** (`accept_counter` action): Accept the customer's
         last counter-offer. Only available when `pending_counter` is set.
       - **Send away**: No sale. Artifact remains in shed. Customer leaves. Market
         Visit AP is consumed.
     - **Multi-item sales (optional, gated by config)**: If `market_multi_item`
       is enabled, a successful sale (match, counter, or settle) does NOT end the
       visit. The customer remains in `negotiating` phase, irritation carries over,
       and the player may offer additional items.
       **Budget pressure**: Each sale ticks `spent_so_far` up. Going over
       `soft_budget` adds +1 irritation (press-your-luck). Sales exceeding
       `absolute_budget` are rejected outright (+2 irritation, no sale).
       A sale within 95%–99.99% of `absolute_budget` awards a 15% precision
       bonus (does not count toward budget pressure). Standing raises the
       soft budget (+5 per point), rewarding loyalists with longer visits.
       The visit ends when the player sends away or the customer storms off.

3. **Customer leaves** if:
   - A sale is agreed (success)
   - Irritation exceeds threshold (failure — customer storms off)
   - Player sends the customer away (neutral — no sale)
   - Rare settle: on mismatch, a random roll against `settle_chance` may cause
     the customer to accept the mismatched item at the low offer price

4. **On successful sale**:
   - Add `offer_value` to both `scrap` and `score`. If the player has 3+ sales
     to this faction, `_apply_loyalty_bonus` applies a 1.05× price multiplier
     (rewarding repeat patronage).
   - Increment `faction_sales[faction_id]` counter
    - Adjust `standing[faction_id]` by a delta that escalates with loyalty:
      - Base: +2 for match (under budget), +1 for match (over budget),
        +1 for accepted counter, **+0 for settle**
      - +1 if artifact was evolved (breakthrough)
      - +1 if 2nd+ sale to this faction (repeat customer bonus)
      - +1 if 4th+ sale to this faction (deep loyalty bonus)
    - Record transcript event
    - Delete ShedItem
    - With multi-item disabled: activity row deleted, `pending_activity_id` cleared
    - With multi-item enabled: activity persists, `pending_activity_id` stays set

5. **On failed/abandoned negotiation**:
   - **Mismatch under irritation threshold (counter-offers disabled)**: Artifact
     returns to Shed unchanged. Activity persists (phase stays `negotiating`),
     player may try another item. No scrap or score. AP is still consumed.
    - **Counter-offer rejected**: The pending counter is cleared and a fresh
      counter is generated for the newly offered item — no irritation is added
      on counter rejection. Player may continue offering other items or send
      away. (Note: the counter-offer rejection mechanic was adjusted during
      implementation; investigate adding irritation-on-reject as a future
      balance tuning lever.)
   - **Customer storms off (irritation exceeds threshold)**: Activity deleted,
     `pending_activity_id` cleared. No scrap or score. AP consumed.
   - **Player sends away**: Activity deleted, `pending_activity_id` cleared.
     No scrap or score. AP consumed.
   - **Settle on mismatch**: Same as successful sale (step 4), but `standing`
     gains +0 instead of +2 (compromised sale).

**Invariants**:
- Selling skill level affects negotiation outcomes (see 6.6)
- Offers are generated fresh per customer interaction — never persisted across
  visits
- Customers do not remember previous offers or visits
- At most ONE customer per Market Visit (but that customer may buy multiple
  items when multi-item mode is enabled)

### 6.6 Skills (Mechanical Effects)

Skills are purchasable per season via the Skills controller (`POST /skills/purchase`).
Each has 3 levels, costs defined in `content/skills.yml`. Effects are applied
at the point of use (draw, push, stop, offer) by reading the character's
skill columns.

**Prospecting (levels 1–3)** — affects artifact drawing and base value:

| Level | Effect |
|-------|--------|
| 1 | `base_value` of drawn artifact increased by +2 |
| 2 | `base_value` increased by +4 total; weight doubled for artifacts with `base_value >= 8` (higher chance of rich finds) |
| 3 | `base_gain_min` and `base_gain_max` each increased by +1 per push |

**Upcycling (levels 1–3)** — reduces instability growth during pushes:

| Level | Effect |
|-------|--------|
| 1 | Instability growth reduced by 1 per push (min 1) |
| 2 | Growth reduced by 2; value gain per push increased by +1 |
| 3 | Growth reduced by 3; value gain increased by +2; `evolution_chance` increased by +0.02 |

Instability growth floors at 1 — even max upcycling cannot fully
eliminate instability.

**Selling (levels 1–3)** — improves market outcomes:

| Level | Effect |
|-------|--------|
| 1 | Estimate range narrowed from ±20% to ±15% at stop time |
| 2 | Irritation gain on mismatches eliminated (gain = 0 instead of 1) |
| 3 | Match multiplier increased from 1.2× to 1.4× `base_multiplier`; one `desired_behaviors` revealed to player |

Skill costs are defined in `content/skills.yml`. Cost scales per level (e.g.
level 1 costs 10 scrap, level 2 costs 25, level 3 costs 50). Skill training
does not cost AP.

### 6.7 Market Dynamics (Supply/Demand)

Three levers create a dynamic pricing economy that penalizes concentration
and rewards market timing. All three operate on the season's `faction_state`
hash, which already tracks `intake_by_trait`, `artifacts_received`, and
`influence` per faction.

#### Trait Saturation

Each artifact trait sold to a faction increases that faction's saturation
for that trait. The effective offer multiplier is reduced:

```
effective_mult = base_multiplier × (1 - sat_rate × trait_count)
```

`sat_rate` defaults to 0.01 per sale. Capped at `max_saturation_discount`
(0.50, preventing offers below 50% of base).

**Effect**: Selling 10 of the same trait drops the multiplier to 0.90×
of base. Penalizes mono-trait farming and rewards diversification.

#### Daily Faction Appetite

Each faction has a `daily_appetite_base` (per-faction, 2–4). After receiving
that many artifacts in a single day, all subsequent offers from that faction
get a `post_appetite_penalty` multiplier (default 0.50×). Resets at daily
maintenance.

**Effect**: Prevents dumping 10 items on the same faction in one day.
Encourages rotating between factions.

#### Desperation Mechanic

Track `days_since_purchase` per faction. If a faction hasn't bought any
artifacts in `desperation_days` (per-faction, 2–4), their next customer
visit gets a `desperation_bonus` multiplier (default 1.30×, configurable
via `market_desperation_bonus`).

**Effect**: Factions cycle between hungry and satiated. A faction you
haven't sold to in a while pays a premium. Rewards rotating between
factions and sitting on inventory.

#### Application

The `_dynamic_multiplier` method in MarketVisit computes the effective
multiplier as:

```
mult = base_multiplier
  × (1 − total_trait_saturation)
  × (appetite_penalty if daily_intake ≥ appetite_base)
  × (desperation_bonus if days_since_purchase ≥ desperation_days)
```

This replaces the raw `base_multiplier` in both match and no-match offer
calculations. The desperation and saturation states are maintained in
`season.faction_state` and updated in `_do_sale` (daily_intake++,
days_since_purchase=0) and daily maintenance (daily_intake=0,
days_since_purchase++).

#### Planned (not yet implemented)

- **Desperate Recruiter**: When a faction trails significantly in influence,
  random events offer premium standing gains or bonus scrap. Gated behind
  `faction_sales[faction_id] >= 1`.

---

## 7. Faction System

### 7.1 Factions (content-driven, loaded from YAML config)

| ID | Name | Interests | Base Mult | Daily Appetite | Desperation Days | Disposition |
|----|------|-----------|-----------|----------------|------------------|-------------|
| syndicate | The Syndicate | thermal, storage, food_processing, power | 1.1 | 3 | 3 | commercial_resale |
| libremount | LibreMount | thermal, water, sanitation, medical_response, power | 0.9 | 4 | 2 | public_distribution |
| faculty | The Faculty | signal, revelation, field, medical_response | 1.0 | 3 | 3 | scholarly |
| purifiers | The Purifiers | force, instability, medical_response | 1.2 | 2 | 4 | destruction |
| revelationists | The Revelationists | revelation, signal, field, transformation | 0.8 | 3 | 2 | sacred_custody |

Faculty has a special rule: its `effective_multiplier` increases for evolved
(breakthrough) artifacts.

Factions are defined as configuration data, NOT as class hierarchies. A
FactionRegistry loads the YAML definition. Subclass behavior is only justified
when a faction has structurally unique mechanics (e.g., Faculty's evolved
artifact premium).

### 7.2 Three-Layer Faction Model

Factions have three connected layers — all three are implemented:

**Personal Standing** ("What do they think of me?"):
- Per-character integer per faction
- Increased by selling to them: +2 on match, +1 on mismatch, +1 bonus for evolved artifacts
- Affects: customer frequency (standing-weighted random selection), prices (+0.05 multiplier per standing point), commissions, special text, faction access
- Stored in `character.standing` map

**Faction Influence** ("How powerful is this faction this season?"):
- Aggregate of all sales to this faction across all players
- Updated atomically in `_do_sale` — adds sale value to influence, increments artifacts_received, tracks intake_by_trait
- Affects: Crier reports, customer mix, Bazaar conditions, rival behavior
- Stored in `season.faction_state` (influence value, artifacts_received, intake_by_trait, name)

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
maintenance_window_minutes: 5   # reserved — route guard is currently a simple
                                # boolean gate during the callback
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
4. Generate Town Crier message: diff current `faction_state` against
   `crier_snapshot`, select highest-priority message template, fill with
   faction name and values. Store in `crier_message`.
5. Update `crier_snapshot` to current `faction_state`.
6. Write FactionSnapshot rows: for each faction in `faction_state`, create
   a snapshot row with season_id, day, faction_id, influence,
   artifacts_received, intake_by_trait.
7. **Reset market dynamics state**: For each faction in `faction_state`:
   `daily_intake = 0` and `days_since_purchase++`.
8. Log transcript event with full faction_state.
9. Preserve activity rows — in-progress prospecting survives rollover
10. If `season.day > season_length`, emit a warning (season end is manual)

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

Admin-triggered via CLI (`create-season`) or auto-created by `Game::show`
when a player visits `/game` after the previous season was archived. Creates
a new Season record with status `active`, day 1. Season length is a game
constant (e.g., 30 days). When a player joins mid-season, their character
is created with full AP at the current season day.

### 8.3 Season End (Finalization)

Admin-triggered via `end-season` CLI or `POST /season/end` web button
(both call `Model::Season::finalize`). MUST execute in this exact order:

1. Compute final leaderboard rank for each character
2. **Clearance sale**: All unsold ShedItems for this season are liquidated at
   25% of their `decayed_value`. The scrap and score are awarded to each
   character before SeasonRecords are built. This ensures no artifact value
   is lost to the aether — even unsold inventory contributes to final score.
   Clearance amount is recorded in `story_highlights.clearance_bonus`.
3. For each SeasonalCharacter:
   a. Collect final stats (score includes clearance, scrap includes clearance,
      standing, faction_sales, skills)
   b. Collect significant ArtifactDisposition records
   c. Build SeasonRecord (score, scrap, rank, standing snapshot, skills
      snapshot, disposition summaries, narrative hooks, clearance_bonus)
   d. Store SeasonRecord (append-only, survives deletion)
4. Verify ALL SeasonRecords are stored successfully
5. Discard all ShedItems for this season (already liquidated in step 2)
6. Delete ALL SeasonalCharacter rows for this season
7. Clear SeasonFactionState (via `nullCol`)
8. Set Season.status = "archived"

On the next visit to `/game`, the player sees a `season_recap` card
with their final score, rank, scrap, standing, and highlights (including
clearance bonus if any). A new active season is auto-created and a fresh
character issued.

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
│ name: "J"  │──────FK────→│ char_id: "abc"          │
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
    { idle => ['begin'], negotiating => ['offer', 'send_away', 'accept_counter', 'stand_pat'] }
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
| negotiating | offer | Receive `shed_item_id`. Match `desired_behaviors` vs item `behaviors`. Match → auto-sale. Mismatch → roll against `settle_chance`; on settle → sale at lowball, on fail → if counter-offers enabled → `counter_offer`; else → increment irritation and `no_match`. At irritation threshold → `customer_left` (storm off). | Match/settle/customer_left/send_away (single-item mode): `$self->delete`, `$char->save`. Match (multi-item mode): `$self->save`. No_match: `$self->save`, `$char->save`. |
| negotiating | accept_counter | Accept pending counter-offer. Triggers sale at counter price. | Same as match/above. |
| negotiating | stand_pat | Player demands original price (no counter). Roll against `chance = 0.30 + (selling * 0.15) + (standing * 0.02)`, capped at 0.85. Success → sale at `floor(decayed_value × dynamic_multiplier)`. Failure → irritation++, if threshold exceeded → storm off. | Success: `$self->delete`, `$char->save`. Failure/normal: `$self->save`, `$char->save`. |
| negotiating | send_away | Player ends negotiation. No sale. | `$self->delete`, `$char->save` |

The `offer` action takes a `shed_item_id` parameter identifying which artifact
from the player's shed is being offered. The `stand_pat` action is available
when a `pending_counter` is set — the player demands the original (non-counter)
price and the customer may accept or refuse based on a skill+standing roll.
Counter-offers and multi-item visits are optional features gated by config
flags (`market_counter_offers`, `market_multi_item`), both enabled by default.
When multi-item is enabled, a sale does not end the visit — irritation carries
over as the press-your-luck mechanism.

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
| Root | index | Gateway redirect (always → /game) |
| Sessions | login_form, create, destroy, logout | Authentication. `login_form` redirects to `/game`. |
| Player | show, destroy | Current player JSON/fragment; delete account |
| Result | show, dismiss | `GET /result` — displays stored outcome (collapse, breakthrough, sold, storm off, etc.). `POST /result/dismiss` — clears result and returns to home view. |
| Game | show | Game state page. Renders login form inline when unauthenticated. Auto-creates character on first visit. After a season ends, first visit shows `season_recap` and auto-creates a new season + fresh character. |
| Nav | show | `GET /nav` — returns tabs (active/inactive + reasons), current view, fragment URLs, context bar. Backend-managed UI state. |
| Idle | show | `GET /idle` — idle action panel (Prospect/Bazaar buttons). Returns 204 when activity active. |
| Crier | show | `GET /crier` — current season's Town Crier message. Returns 204 when no active season. |
| Prospecting | begin, push, stop, show | Prospecting lifecycle + `GET /prospecting` fragment/JSON. |
| Market | begin, offer, send_away, accept_counter, stand_pat, show | Market negotiation lifecycle + `GET /market` fragment/JSON. |
| Shed | index | List shed contents with condition and estimates. |
| Skills | index, purchase | View available skills, purchase upgrade. |
| Factions | show | `GET /factions` — faction registry with standing and influence. Returns 204 when no active season. |
| Home | show | `GET /home` — home dashboard with station status, shed ledger, and contextual suggestions. |
| Leaderboard | index, factions | Player rankings; faction influence time series. |
| Account | show | `GET /account` — account settings panel (logout, delete account). Returns 204 when not logged in. |

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
   to `/game`.
- **Current player**: `GET /player` — returns current player info if logged
   in, 401 if not.
- **Login form**: Inline in `/game` template (device frame with SOFTWARE REGISTRATION
   panel). `GET /login` now redirects to `/game`.
- **Root gateway**: `GET /` — redirects to `/game` (both authenticated and
   unauthenticated; the game template renders the login form when not logged in).

---

## 12. Content System (YAML-Driven)

### 12.1 Directory Structure

```
content/
  bots.yml                        # Bot profile definitions (push/sell policies, skills)
  prospecting.yml                 # All artifact definitions
  skills.yml                      # Skill definitions and costs
  factions.yml                    # Faction definitions
  flavor/
    advisories.yml                 # System advisory messages (idle, season end, faction hunger)
    crier.yml                      # Daily maintenance messages (surge, slump, etc.)
    negotiation_reactions.yml      # Per-faction flavor text for market visit outcomes
    commission_triggers.yml        # Commission issuance text (unused until §7.3)
    system_messages.yml            # Unit status flavor text (device frame boot message)
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

**crier.yml**: Contains all Crier message categories under `crier_messages`:
`faction_surge`, `faction_slump`, `faction_dominance`, `milestone`,
`season_opening` (day 1), `daily_progress` (ranged by day percentage),
and generic fallback messages. Loaded at startup by `Crier.pm`.

**customer_offers.yml** (future): Per-faction customer offer text, tiered
by match quality.

**commission_triggers.yml**: Per-faction narrative text for commission
issuance. Content-only — loaded by the Commission System when implemented.

**negotiation_reactions.yml**: Per-faction flavor text for market visit
outcomes (match, settle, mismatch, storm_off). Loaded lazily by
`MarketVisit::_reactions` on first offer. Falls back to generic text if
no faction entry exists.

### 12.5 Content Loading

The app class sets `content_filename` to the full path of the activity's YAML
file. `load_content` is called once at startup on the global instance. The
parsed data is stored in `content_data` and automatically propagated to
per-request activity instances via the overridden `get()`/`create()` methods.

Skill definitions are loaded by the `skills_data` helper (registered in
`MagicMountain.pm`) from `content/skills.yml` and made available to the
Skills controller and game templates.

Adding a new artifact requires editing `content/prospecting.yml` — no code
changes, no manual registration.

---

## 13. API Endpoints

### 13.1 Endpoint Table

| Method | Path | Controller#Action | Format | Purpose |
|--------|------|-------------------|--------|---------|
| GET | `/` | `Root#index` | — | Gateway redirect (→ `/game`) |
| GET | `/login` | `Sessions#login_form` | — | Redirects to `/game` (login form is inline in game page) |
| POST | `/sessions` | `Sessions#create` | JSON | Login or auto-create player |
| DELETE | `/sessions` | `Sessions#destroy` | JSON | Logout (API) |
| GET | `/logout` | `Sessions#logout` | — | Logout (browser, redirects to `/game`) |
| GET | `/game` | `Game#show` | JSON + HTML | Game state page. Renders login form inline when unauthenticated. |
| GET | `/nav` | `Nav#show` | JSON | Nav state: tabs, current view, fragment URLs, context bar |
| GET | `/player` | `Player#show` | JSON + fragment | Current player info |
| DELETE | `/player` | `Player#destroy` | JSON | Delete account |
| GET | `/crier` | `Crier#show` | JSON + fragment | Crier bulletin. 204 when no active season. |
| GET | `/idle` | `Idle#show` | JSON + fragment | Idle action panel (Prospect/Bazaar buttons). 204 when activity active. |
| GET | `/prospecting` | `Prospecting#show` | JSON + fragment | Prospecting scan |
| GET | `/market` | `Market#show` | JSON + fragment | Market negotiation |
| GET | `/shed` | `Shed#index` | JSON + fragment | Shed ledger |
| GET | `/skills` | `Skills#index` | JSON + fragment | Skill tree |
| GET | `/factions` | `Factions#show` | JSON + fragment | Faction registry. 204 when no active season. |
| GET | `/account` | `Account#show` | JSON + fragment | Account settings (logout, delete account). 204 when not logged in. |
| GET | `/home` | `Home#show` | JSON + fragment | Home dashboard with station status, shed ledger, and suggestions |
| GET | `/result` | `Result#show` | JSON + fragment | Result display (outcome card for collapse, breakthrough, sale, etc.) |
| GET | `/leaderboard` | `Leaderboard#index` | JSON + fragment | Player rankings |
| GET | `/leaderboard/factions` | `Leaderboard#factions` | JSON | Faction influence time series |
| POST | `/result/dismiss` | `Result#dismiss` | JSON | Clear result and return to home view |
| POST | `/prospecting/begin` | `Prospecting#begin` | JSON | Start prospecting (costs 2 AP) |
| POST | `/prospecting/push` | `Prospecting#push` | JSON | Destabilize artifact |
| POST | `/prospecting/stop` | `Prospecting#stop` | JSON | Halt, create shed entry |
| POST | `/market/begin` | `Market#begin` | JSON | Start market visit (costs 1 AP) |
| POST | `/market/offer` | `Market#offer` | JSON | Offer shed item to customer |
| POST | `/market/send_away` | `Market#send_away` | JSON | End negotiation, no sale |
| POST | `/market/accept_counter` | `Market#accept_counter` | JSON | Accept customer's counter-offer |
| POST | `/market/stand_pat` | `Market#stand_pat` | JSON | Hold firm at original price; customer may accept (skill+standing roll) or refuse (irritation++) |
| POST | `/skills/purchase` | `Skills#purchase` | JSON | Buy skill upgrade (costs scrap) |

### 13.2 Self-Describing Actions Convention

Every JSON response from a view-state endpoint (prospecting, market, shed,
skills, idle, account) includes a `_self` block with an `actions` array. Each
action entry describes one available interaction:

```
{ "_self": { "actions": [
  { "url": "/prospecting/push", "method": "POST", "label": "Push",
    "id": "btn-push", "class": "mm-btn-primary" },
  ...
]}}
```

Fields:

| Field | Required | Description |
|-------|----------|-------------|
| `url` | yes | POST endpoint URL |
| `method` | yes | HTTP method (typically POST or DELETE) |
| `label` | yes | Human-readable button text |
| `id` | no | DOM element id |
| `class` | no | CSS class string for styling |
| `confirm` | no | If present, JS shows a confirm() dialog with this text before submitting |
| `redirect` | no | If present, JS redirects here after success instead of re-fetching /game |
| `disabled` | no | If true, button is rendered with a disabled attribute |
| `data` | no | Hash of key-value pairs, each rendered as a `data-*` attribute on the button. Sent as JSON body parameters on click. |

**Client contract**: JS never hardcodes an action URL. It reads `data-action-url`
from rendered buttons (which come from the component). Any consumer (walkthrough,
bot, third-party) can discover available actions from the JSON `_self.actions`
block without parsing HTML.

**Nav tab contract**: The `GET /nav` response includes an `action_url` field on
tabs that auto-begin an activity (e.g., prospect tab → `/prospecting/begin`).
When present, the client POSTs to that URL instead of simply switching views.
This eliminates all hardcoded begin-activity endpoints from the client.

**Template contract**: All action buttons are rendered via the shared component
`templates/components/action_buttons.html.ep`. Fragment templates hardcode
neither URLs nor button HTML — they pass an `actions` arrayref to the component
and let it generate the markup.

### 13.3 Controller Action Contracts

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

**Market#accept_counter**: Requires activity `type == "market_visit"` and
`phase == "negotiating"` and a pending counter-offer on the customer.
Triggers sale at the counter price. Returns same result shapes as a match
sale (`sold` or `sold_more` in multi-item mode).

**Market#send_away**: Requires activity `phase == "negotiating"`. Ends
negotiation without sale. Artifact remains in shed. Activity row deleted.

**Nav#show**: No activity required. Returns JSON with `current_view` (stored
or activity-forced), `tabs` (id/label/active/reason/fragment_url per tab),
`primary_fragment_url`, `secondary_view`, `secondary_fragment_url`, and
`context` text. Accepts optional `X-Nav-View` header to request a view
transition (server validates tab active state, persists choice to character).
Serves as the single source of UI state — JS is declarative, never computes
view logic or URLs.

**Idle#show**: Returns 204 when an activity is in progress. Otherwise returns
JSON (`can_prospect`, `can_market`, `shed_count`) or the idle actions fragment
with Prospect/Bazaar buttons.

**Crier#show**: Returns 204 when no active season. Otherwise returns the current
season's `crier_message` as JSON or the crier bulletin fragment.

**Factions#show**: Returns 204 when no active season. Otherwise returns faction
registry as JSON (`factions`, `standing`, `faction_sales`, `faction_state`) or
fragment.

**Account#show**: Returns 204 when not logged in. Otherwise returns account
settings panel (logout, delete account) as fragment.

**Shed#index**: No activity required. Returns all ShedItems for the character
with condition, estimated value range, artifact name, and age. Supports query
filtering (condition, artifact_id, behavior, value range) and sorting.

**Skills#index**: Returns skill definitions from YAML plus the character's
current skill levels.

**Skills#purchase**: Receives `skill_id`. Validates character has enough scrap
and current level < max_level. Deducts scrap. Increments skill level on
character.

### 13.4 Response Shape for Game State

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
  "season": { "day": 5, "total_days": 30, "label": "Season 1" },
  "world_message": "The air tastes faintly of ozone...",
  "csrf_token": "aB3x...",
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
identical to human play. The simulation framework lives across three layers:

- **`MagicMountain::Bot::PushPolicy`** — stateless evaluation of push/stop
  decisions given character state, artifact state, and policy parameters.
- **`MagicMountain::Bot::SellPolicy`** — stateless evaluation of three
  selling decisions: accept customer, offer item, try another after mismatch.
- **`Command::simulate`** — orchestrates the simulation loop, creates bot
  accounts/characters, drives prospecting and market phases, calls policies,
  and records transcripts.

### 14.1 CLI Interface

```
perl -Ilib script/mountain simulate [OPTIONS]

Options:
  --count N             Number of bots (default 5)
  --days N              Season length in days (default 30)
  --seed N              RNG seed for reproducibility
  --output FILE         Transcript output path
  --profile FILE        Bot profile YAML (default content/bots.yml)
  --profile-weights W   Weighted profile distribution, e.g. 'a=3,b=1'
  --skill-profile S     Skill levels (only when using inline default profile)
  --counter-offers      Enable counter-offer haggle step
  --multi-item          Enable multi-item sales per market visit
```

### 14.2 Push Policies

Registered in `MagicMountain::Bot::PushPolicy`. Each policy is a function that
receives `($char, $artifact, $params)` and returns true when the bot should
STOP pushing (i.e., stop condition met).

| Policy | Parameters | Behavior |
|--------|------------|----------|
| `fixed_pushes` | `max` (default 3) | Push exactly N times, then stop |
| `instability_cap` | `max` (default 5) | Push until instability exceeds cap |
| `stage_guard` | `stop_at` (default "unstable") | Push until target stage reached |
| `greed` | `prob` (default 0.7) | Push with probability P each time |
| `value_target` | `min` (default 20) | Push until value exceeds target |
| `composite_and` | `policies` (sub-policy array) | Stop only when ALL sub-policies say stop |
| `composite_or` | `policies` (sub-policy array) | Stop when ANY sub-policy says stop |

### 14.3 Selling Policies

Registered in `MagicMountain::Bot::SellPolicy`. Selling is decomposed into
four separate decisions, each with its own policy dispatch:

| Decision | Policy | Parameters | Behavior |
|----------|--------|------------|----------|
| **accept_customer** | `faction_loyalist` | `faction` | Only enter market if customer matches target faction |
| | `hoarder` | *(none)* | Never enter market |
| | `default` | *(none)* | Accept any customer |
| **should_offer_item** | `highest_offer` | `min_value` (default 10) | Only offer items above a value threshold |
| | `default` | *(none)* | Offer any item in shed |
| **try_another** | `opportunist` | *(none)* | Stop offering after first mismatch (never try another) |
| | `default` | *(none)* | Continue offering further items |
| **should_accept_counter** | `default` | `haggle_aggression` (default 1.0), `min_counter_pct` (default 0) | Accept if `rand() < aggression` AND `counter_value >= decayed_value × min_pct` |
| | `highest_offer` | *(none)* | Never accept counters |

### 14.4 Bot Strategy Profile

Bot profiles are defined in `content/bots.yml`:

```yaml
- id: stage_guard_opportunist
  display_name: "Cautious"
  push_policy: { name: "stage_guard", params: { stop_at: "unstable" } }
  sell_policy: { name: "opportunist" }
  skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }

- id: greed_desperate
  display_name: "Risk Taker"
  push_policy: { name: "greed", params: { prob: 0.8 } }
  sell_policy: { name: "desperate" }
  skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }

- id: value_hoarder
  display_name: "Hoarder"
  push_policy: { name: "value_target", params: { min: 30 } }
  sell_policy: { name: "hoarder" }
  skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }

- id: fixed_highest
  display_name: "Measured"
  push_policy: { name: "fixed_pushes", params: { max: 2 } }
  sell_policy: { name: "highest_offer", params: { min_value: 18 } }
  skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }

- id: instability_loyalist
  display_name: "Loyalist"
  push_policy: { name: "instability_cap", params: { max: 3 } }
  sell_policy: { name: "faction_loyalist", params: { faction: "syndicate" } }
  skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }

And four additional loyalist variants pairing faction_loyalist with different
push policies (fixed_pushes, stage_guard, greed, value_target).
```

The `faction_loyalist` sell policy combined with any push policy produces
a loyalist bot that sells exclusively to one faction. The `hoarder` policy
skips market entirely, accumulating shed items until season end.

Profiles are selected per-bot either by round-robin, or by weighted random
selection via `--profile-weights` (e.g. `--profile-weights 'stage_guard_opportunist=3,value_hoarder=1'`).

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

## 18. Activity Registration

Activity types are registered manually in `MagicMountain.pm` as explicit `has`
attributes. Each global instance is constructed with its persistence file,
content YAML path, and app reference, then calls `load_content` to parse its
YAML definitions. Adding a new activity type requires:

1. Creating the subclass in `lib/MagicMountain/Activity/`
2. Adding a `has` declaration to `MagicMountain.pm` with the constructor call
3. Adding the activity's controller routes in `buildRoutes`

There is no dynamic scanning or automatic registry. The two current activities
are `$app->prospecting` and `$app->market`, directly available to controllers
at request time.

---

## 19. Implementation Status (New Codebase)

The new codebase (`lib/`) is a ground-up rebuild.

### 19.1 Implemented

| Feature | Module(s) | Notes |
|---------|-----------|-------|
| **Model persistence layer** | `Model.pm`, `Model::Account`, `Model::Character`, `Model::Season`, `Model::Session`, `Model::AuditLog` | JSON file CRUD, UUID, atomic write-via-temp-file |
| **Routing gateway** | `Controller::Root` | `GET /` redirect |
| **Login flow** | `Controller::Sessions` | Auto-creates accounts on first login |
| **Player info** | `Controller::Player` | `GET /player` JSON or 401 |
| **Game page** | `Controller::Game`, `Controller::Nav`, `templates/game/show.html.ep`, `public/js/game.js` | Device-frame layout with pinned chrome (header, status strip, nav bar, context bar) and two-panel center area. `GET /nav` drives all panel content via server-provided fragment URLs. JS is purely declarative — no view logic, no URL computation. |
| **Nav controller** | `Controller::Nav` | `GET /nav` returns current view, tab states (active/inactive + reasons), fragment URLs (primary + secondary per tab), context bar text. Backend-managed UI state. Testable via `t/nav_web.t`. |
| **Session management** | `Model::Session`, `current_player` helper | Configurable inactivity timeout |
| **CLI commands** | `Command::create_account`, `Command::list_accounts`, `Command::delete_account`, `Command::disable_account`, `Command::create_season`, `Command::end_season`, `Command::advance_day`, `Command::simulate` | Account lifecycle, season management, day rollover, bot simulation |
| **Layout** | `templates/layouts/default.html.ep` | Minimal layout — monospace font stack (`IBM Plex Mono`), custom CSS only (`/css/app.css`). No Bootstrap. |
| **Day maintenance** | `Maintenance.pm` | IOLoop timer, route gating, `on_maintenance` callback for AP refresh, day increment, decay |
| **Audit logging** | `Model::AuditLog` | JSONL login/logout/account events |
| **Activity base class** | `Activity.pm` | State-machine dispatch, column accessors, content loading |
| **Prospecting activity** | `Activity::Prospecting` | Push/collapse/breakthrough math, stop → shed entry, activity-owned persistence |
| **MarketVisit activity** | `Activity::MarketVisit`, `Controller::Market` | Customer generation, match-based selling, settle rolls, irritation tracking, empty shed guard, skill effects |
| **ShedItem model** | `Model::ShedItem` | `shed.json` CRUD, per-character queries |
| **Character invariants** | `Model.pm` validate hook, `Model::Character` override | AP bounds, scrap non-negative, score never decreases, skills 0–3 |
| **Character column expansion** | `Model::Character` | `action_points`, `action_points_max`, skill columns |
| **Prospecting/Market controllers** | `Controller::Prospecting`, `Controller::Market` | Thin dispatch+render, no persistence |
| **Shed controller** | `Controller::Shed` | `GET /shed` with query-string filtering (condition, artifact_id, behavior, min/max value, sort, order); `respond_to` JSON/HTML |
| **Home controller** | `Controller::Home` | `GET /home` — home dashboard with station status, contextual suggestions, shed ledger preview |
| **Result controller** | `Controller::Result` | `GET /result` displays outcome cards (collapse, breakthrough, sale, storm-off); `POST /result/dismiss` clears result and returns to home |
| **Skills controller + purchase** | `Controller::Skills`, `skills_data` helper | `GET /skills` lists YAML definitions + current levels; `POST /skills/purchase` validates scrap, enforces level cap, deducts and increments |
| **Leaderboard controller** | `Controller::Leaderboard` | `GET /leaderboard` — seasonal character rankings sorted by score |
| **Content YAML** | `content/prospecting.yml`, `content/skills.yml`, `content/factions.yml`, `content/bots.yml`, `content/flavor/negotiation_reactions.yml` | Artifact definitions (with decay_modifiers), skills (with per-level costs), factions, bot profiles, per-faction negotiation flavor text |
| **Transcript system** | `Model::Transcript` | JSONL event log with narrative, integrated into all activity handlers and simulation |
| **Bot simulation** | `Command::simulate`, `Bot::PushPolicy`, `Bot::SellPolicy`, `content/bots.yml`, `bin/analyze_sim` | Pluggable push/sell policies, YAML profile definitions, weighted profile distribution, reproducible simulation, analysis script |
| **Artifact decay** | `ShedManager.pm`, `Maintenance.pm`, `Activity::Prospecting` | Smooth daily linear interpolation; per-artifact `decay_modifiers` from YAML; `fresh`/`settling`/`fading` stages; estimate range updates; optional `decay_tick` transcript events gated by flag |
| **Season-aware character lookup** | `Controller.pm` base class, `MagicMountain.pm` | `_require_character` filters by active season; `active_season` method (non-memoized, fresh each call) on app class |
| **JS client** | `public/js/game.js` | Declarative JS: fetches `/game` for boot state, fetches `/nav` for panel layout, renders server-provided fragment URLs into primary/secondary panels. No view logic, no URL computation, no HTML template literals. Event delegation on panel containers for action buttons. |
| **Fragment rendering** | All resource controllers (`Player`, `Crier`, `Idle`, `Home`, `Result`, `Prospecting`, `Market`, `Shed`, `Skills`, `Factions`, `Leaderboard`, `Account`) | Each controller provides `respond_to json` + `_format=fragment` HTML. JS fetches fragment URLs from `/nav` response and renders via `innerHTML`. No client-side HTML construction. |
| **Settle rolls** | `Activity::MarketVisit.pm` | On mismatch, 15% chance customer accepts lowball; configurable per-faction |
| **ArtifactDisposition records** | `Model::ArtifactDisposition.pm` | Append-only per-sale records with artifact snapshot, faction, standing/influence deltas; created in `_do_sale` |
| **Crier daily progress** | `Crier.pm`, `content/flavor/crier.yml` | Day-range messages (early/mid/late season) as fallback when no faction events fire |
| **Season finalization CLI** | `Command::end_season.pm`, `Model::Season.pm` (finalize) | 8-step archive: clearance sale (25% of shed value), compute leaderboard, build SeasonRecords, discard shed/characters, clear faction_state, archive. CLI-only — no web UI button. |
| **Clearance sale** | `Model::Season.pm` (finalize) | Unsold shed items liquidated at 25% of `decayed_value` during season finalization; awarded as scrap+score before SeasonRecord creation |
| **Loyalty standing escalation** | `Activity::MarketVisit.pm`, `Model::Character.pm` | Standing delta grows with repeat sales: +2 match / +1 mismatch base, +1 evolved, +1 at 2nd+ sale, +1 at 4th+ sale; loyalty access guarantee redirects customers to top faction after 3 off-faction visits |
| **SeasonRecord model** | `Model::SeasonRecord.pm` | Post-season archive per character: score, scrap, rank, standing/skills snapshots, story highlights |
| **Season recap + auto-renew** | `Controller/Game.pm`, `public/js/game.js` | On first `/game` visit after end-season, shows recap card, auto-creates new season + fresh character |
| **CSRF protection** | `MagicMountain.pm` (csrf_token helper, auth_write bridge), `Controller/Sessions.pm`, `Game.pm`, `public/js/game.js` | Session-based token returned on login, sent as `X-CSRF-Token` header on all authenticated write requests |
| **Faction snapshot history** | `Model::FactionSnapshot.pm`, `Maintenance.pm`, `Season.pm` (finalize), `Controller/Leaderboard.pm` (factions) | Daily faction influence persisted during maintenance and season end; `GET /leaderboard/factions` returns per-faction time series |
| **`nullCol` helper** | `Model.pm` | `delete` a column from row (avoids JSON `null` artifacts from `setCol($col, undef)`) |
| **Shared mtime cache** | `Model.pm` | mtime:size file signature cache (`%_mtime_for`); avoids redundant reloads when multiple saves happen in the same request. Cross-process safe in prefork mode — no per-process sequence counter. |
| **Narrative reactions** | `Activity::MarketVisit.pm`, `content/flavor/negotiation_reactions.yml` | Per-faction flavor text for match/settle/mismatch/storm_off outcomes; `{item_id}`/`{value}` template substitution; falls back to hardcoded text |
| **Loyalty price bonus** | `Activity::MarketVisit.pm` (`_apply_loyalty_bonus`) | 1.05× offer multiplier for 3+ sales to the same faction |
| **Loyalty access guarantee** | `Activity::MarketVisit.pm` (begin), `Model::Character.pm` (`loyalty_visits_since`) | After 3 consecutive market visits to non-top-faction customers, forcibly redirects to player's top faction |
| **Expanded artifact pool** | `content/prospecting.yml` | Expanded from minimal set to 20+ artifacts across multiple archetypes and behaviors |
| **Analysis script** | `bin/analyze_sim` | Reusable transcript analysis: per-bot scores, push/sell counts, match rates |
| **Rate limiting** | `MagicMountain::RateLimiter.pm`, `MagicMountain.pm` (bridge, helper, config), `Controller/Sessions.pm` (recording) | IP-based + account-name-based rate limiting on login; Retry-After, X-RateLimit-* headers; configurable window/attempts/block |
| **Counter-offers** | `Activity/MarketVisit.pm` (offer/accept_counter), `Controller/Market.pm`, `Bot/SellPolicy.pm` | Optional, gated by `market_counter_offers` config (default on). Customer counters at midpoint price; player may accept or reject. |
| **Multi-item sales** | `Activity/MarketVisit.pm` (offer), `Controller/Market.pm` | Optional, gated by `market_multi_item` config (default on). Multiple sales per visit with budget pressure and irritation carryover. |
| **Stand-pat mechanic** | `Activity/MarketVisit.pm` (stand_pat), `Controller/Market.pm` | Player demands original (non-counter) price; customer accepts based on `0.30 + selling*0.15 + standing*0.02` roll (capped 0.85). Failure adds irritation, may trigger storm-off. |
| **Market dynamics** | `Activity::MarketVisit.pm` (`_dynamic_multiplier`) | Trait saturation (0.01/sale), daily faction appetite (2–4/day), desperation bonus (1.30× after idle); configured via defaultConfig and per-faction YAML |

### 19.2 Needs Update (Existing Code to Refactor)

| Module | Change Required |
|--------|-----------------|
| *(none currently identified)* | |

### 19.3 Planned (Not Yet Implemented)

| Feature | Priority | Notes |
|---------|----------|-------|
| Commission system | Low | Faction notices, active commissions |
| Desperate Recruiter (underdog catch-up) | Low | Premium standing/bonus for selling to trailing factions |

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

## 21. UI Design References

| Document | Purpose |
|----------|---------|
| `docs/design_bible.md` | Visual design language: palette, typography, ProspectBoy 3000 device fiction, faction iconography, panel language |
| `docs/nav_state_rules.md` | Nav state model: views, tab active/inactive rules, secondary panel mapping, context bar text |

---

## 22. Directory Layout

```
magic_mountain/
├── AGENTS.md                      # Project guide for AI agents
├── GAME_ARCHITECTURE.md           # Target architecture spec (authoritative)
├── FUTURES.md                     # Planned work beyond current implementation
├── Makefile                       # test, cover, indent targets
├── TUNING.md                      # Balance tuning reference
├── cpanfile                       # Perl dependencies (Mojolicious, YAML::XS, etc.)
├── magic_mountain.yml             # App config (secrets, session_timeout_minutes, end_of_day_hour)
├── opencode.json                  # opencode configuration
├── package.json                   # Node tooling (JS syntax check)
│
├── bin/                           # Utility scripts
│   ├── analyze                    # Simulation analysis
│   ├── analyze_sim                # Transcript analysis
│   ├── check_coverage             # Faction-artifact coverage validation
│   ├── check_loyalist_balance     # Loyalist strategy viability check
│   ├── find_dead_code             # Dead code detection
│   ├── run_many                   # Batch simulation runner
│   ├── run_sims                   # Simulation runner
│   ├── setup_ramdisk              # RAM disk setup for sim speed
│   ├── smoke_test_endpoint        # Endpoint smoke test
│   └── walkthrough                # End-to-end game loop walkthrough
│
├── lib/
│   ├── MagicMountain.pm              # Mojolicious app: routes, helpers, attributes
│   └── MagicMountain/
│       ├── Activity.pm               # Base class for state-machine activities
│       ├── Controller.pm             # Base controller
│       ├── Crier.pm                  # Town Crier narrative generation
│       ├── Maintenance.pm            # In-process daily maintenance timer
│       ├── Model.pm                  # Base persistence class (JSON file CRUD, UUID, find)
│       ├── RateLimiter.pm            # IP/account-based rate limiting
│       ├── ShedManager.pm            # Artifact decay logic
│       ├── Activity/
│       │   ├── MarketVisit.pm        # Customer generation, negotiation, sale
│       │   └── Prospecting.pm        # Artifact draw, push/collapse/breakthrough, stop
│       ├── Bot/
│       │   ├── PushPolicy.pm         # Push/stop decision policies
│       │   └── SellPolicy.pm         # Selling decision policies
│       ├── Command/
│       │   ├── advance_day.pm        # CLI: advance-day (manual maintenance trigger)
│       │   ├── create_account.pm     # CLI: create-account
│       │   ├── create_season.pm      # CLI: create-season
│       │   ├── delete_account.pm     # CLI: delete-account
│       │   ├── disable_account.pm    # CLI: disable-account
│       │   ├── end_season.pm         # CLI: end-season (finalization)
│       │   ├── list_accounts.pm      # CLI: list-accounts
│       │   ├── report.pm             # CLI: aggregate transcript stats for tuning analysis
│       │   └── simulate.pm           # CLI: run bot simulation
│       ├── Controller/
│       │   ├── Account.pm            # Account settings panel
│       │   ├── Crier.pm              # Town Crier bulletin
│       │   ├── Factions.pm           # Faction registry
│       │   ├── Game.pm               # Game state page
│       │   ├── Home.pm               # Home dashboard (shed ledger)
│       │   ├── Idle.pm               # Idle action panel
│       │   ├── Leaderboard.pm        # Season leaderboard
│       │   ├── Market.pm             # MarketVisit actions (begin, offer, send_away, accept_counter, stand_pat)
│       │   ├── Nav.pm                # Navigation state (tabs, views, fragment URLs)
│       │   ├── Player.pm             # Current player info
│       │   ├── Prospecting.pm        # Prospecting actions (begin, push, stop)
│       │   ├── Result.pm             # Result display (outcome cards, dismiss)
│       │   ├── Root.pm               # Gateway redirect (GET /)
│       │   ├── Sessions.pm           # Login/logout, session management
│       │   ├── Shed.pm               # Shed inventory listing
│       │   └── Skills.pm             # Skill purchase endpoint
│       └── Model/
│           ├── Account.pm            # Player accounts (username, password)
│           ├── ArtifactDisposition.pm # Per-sale permanent record
│           ├── AuditLog.pm           # JSONL event log
│           ├── Character.pm          # Per-season character (name, score, AP, skills)
│           ├── FactionSnapshot.pm    # Daily faction history
│           ├── Season.pm             # Season config and state
│           ├── SeasonRecord.pm       # Post-season archive
│           ├── Session.pm            # Server-side session tracking
│           ├── ShedItem.pm           # Shed artifact inventory row
│           └── Transcript.pm         # Game event log
│
├── templates/
│   ├── components/
│   │   └── action_buttons.html.ep    # Shared button rendering component
│   ├── layouts/
│   │   └── default.html.ep           # Minimal layout (Normalize.css, IBM Plex Mono)
│   ├── account/
│   │   └── settings.html.ep          # Account settings panel
│   ├── crier/
│   │   └── bulletin.html.ep          # Town Crier message display
│   ├── factions/
│   │   └── registry.html.ep          # Faction registry with standing/influence
│   ├── game/
│   │   └── show.html.ep              # Authenticated home page with game state
│   ├── home/
│   │   └── dashboard.html.ep         # Home dashboard (station status + shed ledger)
│   ├── idle/
│   │   └── actions.html.ep           # Idle action panel (Prospect/Bazaar buttons)
│   ├── leaderboard/
│   │   └── rankings.html.ep          # Player rankings table
│   ├── market/
│   │   └── negotiation.html.ep       # Market negotiation panel
│   ├── player/
│   │   └── status.html.ep            # Player status strip
│   ├── prospecting/
│   │   └── scan.html.ep              # Prospecting scan panel
│   ├── result/
│   │   └── show.html.ep              # Result display (outcome cards, season recap)
│   ├── shed/
│   │   └── ledger.html.ep            # Shed inventory ledger
│   └── skills/
│       └── training.html.ep          # Skill training panel
│
├── public/
│   ├── css/
│   │   └── app.css                   # Custom stylesheet
│   └── js/
│       └── game.js                   # Declarative UI orchestration
│
├── content/                          # YAML content definitions
│   ├── bots.yml                      # Bot profile definitions
│   ├── factions.yml                  # Faction definitions and interests
│   ├── prospecting.yml               # Artifact specs and weights
│   ├── skills.yml                    # Skill tree and costs
│   └── flavor/                       # Narrative text definitions
│       ├── advisories.yml            # System advisory messages (idle, season end, etc.)
│       ├── commission_triggers.yml   # Commission issuance text
│       ├── crier.yml                 # Town Crier daily messages
│       ├── negotiation_reactions.yml # Per-faction market flavor text
│       └── system_messages.yml       # Unit status flavor text (boot message)
│
├── t/                                # Test suite (44 files)
│   ├── lib/
│   │   └── TestCharacter.pm          # Test helper: character factory
│   ├── activity.t                    # Activity base class tests
│   ├── activity_prospecting.t        # Prospecting unit tests
│   ├── bot_simulate.t                # Bot simulation tests
│   ├── command_advance_day.t         # advance-day CLI tests
│   ├── controller_web.t              # Controller integration tests
│   ├── crier.t                       # Crier narrative tests
│   ├── decay.t                       # Artifact decay tests
│   ├── end_season.t                  # Season finalization tests
│   ├── faction_snapshot.t            # Faction snapshot tests
│   ├── faction_stars.t               # Faction stars display tests
│   ├── faction_state.t               # Faction state tests
│   ├── fragment_web.t                # Fragment rendering tests
│   ├── game_web.t                    # Game page integration tests
│   ├── home_web.t                    # Home dashboard web tests
│   ├── js_syntax.t                   # JS syntax validation
│   ├── leaderboard.t                 # Leaderboard tests
│   ├── login.t                       # Login flow integration tests
│   ├── maintenance.t                 # Daily maintenance tests
│   ├── market_dynamics.t             # Market dynamics tests
│   ├── market_visit.t                # MarketVisit unit tests
│   ├── market_visit_web.t            # MarketVisit web integration tests
│   ├── model.t                       # Base Model class tests
│   ├── model_account.t               # Account model tests
│   ├── model_artifact_disposition.t  # ArtifactDisposition tests
│   ├── model_character.t             # Character model tests
│   ├── model_character_invariants.t  # Character invariant tests
│   ├── model_delete.t                # Model delete tests
│   ├── model_save_table_edit.t       # Model save/edit tests
│   ├── model_season.t                # Season model tests
│   ├── model_shed_item.t             # ShedItem model tests
│   ├── model_validate.t              # Model validation tests
│   ├── nav_web.t                     # Nav controller tests
│   ├── prospecting_web.t             # Prospecting web integration tests
│   ├── rate_limiter.t                # Rate limiter tests
│   ├── result_web.t                  # Result page web tests
│   ├── season_end_web.t              # Season end web tests
│   ├── season_recap.t                # Season recap display tests
│   ├── session.t                     # Session lifecycle tests
│   ├── shed.t                        # ShedManager tests
│   ├── shed_web.t                    # Shed web integration tests
│   ├── skills_web.t                  # Skills web integration tests
│   ├── stand_pat_web.t               # Stand-pat web integration tests
│   └── transcript.t                  # Transcript tests
│
├── data/                             # Runtime JSON persistence
│   ├── accounts.json
│   ├── activities.json
│   ├── audit.jsonl
│   ├── characters.json
│   ├── dispositions.json
│   ├── faction_snapshots.json
│   ├── season_records.json
│   ├── seasons.json
│   ├── sessions.json
│   ├── shed.json
│   └── transcript.jsonl
│
├── docs/                             # Design documentation
├── cover_db/                         # Coverage reports (generated)
└── script/mountain                   # App entry point: perl script/mountain <command>
```
