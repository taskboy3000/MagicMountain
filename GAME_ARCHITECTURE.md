# Magic Mountain — Game Architecture

*Intended as a specification for rebuilding this game on a new foundation.
No source code. All mechanics, boundaries, and invariants preserved.*

---

## 1. Game Concept

**Magic Mountain** is a multiplayer seasonal push-your-luck game. Players extract
strange artifacts from a mysterious mountain, destabilize them for greater
value, and sell them to competing factions. Each season is a tournament: highest
cumulative score wins. The game is played through a web UI or automated bot
simulation.

**Core tension**: Every "push" (destabilization attempt) increases an artifact's
value but also raises its risk of catastrophic collapse. Collapse means total
loss — zero salvage. Players decide when to stop and sell.

---

## 2. Core Gameplay Loop

```
Login/join season
  → Begin daily event (consume 1 turn)
    → Artifact is drawn from weighted pool
      → Push (repeatable, no turn cost)
        → Instability grows, value grows
        → Three stages: stable → strained → unstable
        → Possible outcomes per push:
          - Collapse: lose artifact, get nothing
          - Breakthrough: artifact evolves (massive value spike, auto-cashout)
          - Normal: value increases, get new signal text
      → Stop (no turn cost)
        → Up to two faction buyers make offers
          (usually two; falls back to one if only one faction is eligible)
      → Sell (no turn cost)
        → Choose one faction buyer
        → Award scrap (spendable) + score (leaderboard)
        → Pending activity clears
  → Repeat until out of turns
  → Day rollover: full turn refresh, pending activity preserved
  → Season ends after N days (admin-triggered)
```

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
                          │     ├── Mutate $char fields (scrap, score)
                          │     ├── Set phase directly: $self->phase('processing')
                          │     └── Return { view => {...} }
                          │
                          ├── If phase == 'idle': delete activity row, clear FK
                          │     else: $activity->save, $char->setCol('pending_activity_id', $activity->getCol('id'))
                          ├── $char->save — persist character mutations
                          └── Pipe $result->{view} to render/json
```

Controllers are dumb pipes. They do not inspect or filter what the activity
returns. They trust `turns_remaining` as written by maintenance — no rollover
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
  │     (extension point for: increment season.day, refresh turns,
  │      update leaderboard, check season end)
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
- The actual day-rollover logic (turn refresh, day increment) runs in the
  `on_maintenance` callback — a single responsbility extension point that
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
classes (Activity, Market, SeasonalCharacter) without a central dispatcher.

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
| **Controller::*** | App reference, model accessors (accounts, characters, seasons) | Game logic, phase validation, artifact math, persistence orchestration |
| **Activity (base)** | Persisted columns (char_id, type, phase, artifact, offers), ephemeral attributes (transitions, app, content_filename, content_data, log), dispatch logic, get/create overrides for ephemeral propagation, load_content | Game math, artifact knowledge, YAML content interpretation |
| **Activity::*** (subclass, e.g. Prospecting) | App reference, transition table, content interpretation, live activity state (artifact, offers columns), create override (type/phase defaults) | Market, Faction objects, Account model, other players' data |
| **Market** (offer generator) | Faction objects, content reference | Character model, Account model |
| **SeasonalCharacter** (character wrapper) | Model row data hashref, player_id | Market, Faction, Content, Transcript |
| **Model::Character** (persistence) | File path, column definitions, JSON CRUD | Game logic, artifact math, faction rules |
| **Model::Account** (persistence) | File path, column definitions, JSON CRUD | Game logic, season data, character data |
| **Model::Season** (persistence) | File path, column definitions, JSON CRUD | Per-player character data, game logic |
| **Model::Session** (persistence) | File path, column definitions, expiry logic | Game logic, character data |
| **Maintenance** (day scheduler) | App reference, end_of_day_hour, clock, on_maintenance callback | Game math, artifact logic, character internals |
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
- Handler methods (`begin`, `push`, `stop`, `sell`) — one per action in the transition table

### Controller Responsibility

Controllers are dumb pipes. Their entire job:

1. Resolve player identity via `$self->current_player`
2. Load the character model via `$self->app->characters->find(...)`
3. Read `pending_activity_id` from the character
4. Load or create the activity row:
   - `$id = $char->getCol('pending_activity_id')`
   - `$activity = $id ? $self->app->prospecting->get($id) : $self->app->prospecting->create(char_id => $char->getCol('id'))`
5. Delegate to the activity: `$activity->dispatch($char, $action, %params)`
6. If phase is `'idle'` after dispatch: delete activity row, clear FK. Otherwise: `$activity->save`, set FK.
7. Call `$char->save` to persist
8. Pipe the activity's `view` result to the template: `$self->render(json => $result->{view})`

No phase validation. No artifact math. No persistence calls (except the two
saves). No offer generation. No transcript recording. No serialize/deserialize
ceremony. No controller checks for day rollover or refreshes turns.

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

### 5.3 SeasonalCharacter (one per player per season)

| Field | Type | Description |
|-------|------|-------------|
| player_id | UUID | FK to PlayerAccount |
| season_id | UUID | FK to Season |
| display_name | string | Snapshot of name at season start |
| score | integer | Cumulative leaderboard value. NEVER decreases |
| scrap | integer | Spendable currency. May decrease via future purchases |
| turns_remaining | integer | Daily event allowance remaining |
| faction_sales | map | Per-faction sale count this season |
| standing | map | Per-faction reputation integer |
| pending_activity_id | string or null | FK to activities.json row. null when idle |
| current_location | string | Current location ID in the location graph (default: `camp`) |

> **Note on `last_refreshed_day`**: This field existed in the original
> "lazy rollover" design where turns were refreshed on next player action.
> The in-process maintenance design refreshes all turns during the daily
> maintenance window, so this field is no longer needed. Controllers trust
> `turns_remaining` as written.

**Invariants enforced by SeasonalCharacter wrapper:**
- `turns_remaining` cannot go below zero
- `scrap` must be non-negative
- `pending_activity_id` must reference a valid activities.json row if set
- `score` never decreases
- Attempting to consume a daily event when turns are zero is a hard error

**Property distinction:**
- `score` = cumulative seasonal leaderboard value, never decreases
- `scrap` = spendable seasonal currency, may decrease through future systems

### 5.4 Activity (activities.json)

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
    "offers": [ ... ],
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
| type | string | Discriminator (e.g. "prospecting") |
| phase | string | State-machine phase: idle / processing / awaiting_buyer |
| artifact | hashref or null | Live artifact state (null when idle) |
| offers | arrayref or null | Buyer offers (null when not awaiting_buyer) |
| createdAt | unix timestamp | Row creation time |
| updatedAt | unix timestamp | Last save time |

**Prospecting — artifact column shape:**

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

**Prospecting — offers column shape (awaiting_buyer phase only):**

```json
[
  {
    "faction_id": "syndicate",
    "faction_name": "The Syndicate",
    "value": 24,
    "text": "A broker tags it for resale.",
    "disposition": "pragmatic"
  },
  {
    "faction_id": "faculty",
    "faction_name": "The Faculty",
    "value": 29,
    "text": "A scholar notes the signal.",
    "disposition": "scholarly"
  }
]
```

**Critical rule**: Once offers are generated at stop time, they are persisted
in the offers column and MUST NOT be rerolled at sell time. The sell action
validates the submitted faction against stored offers and returns the exact
stored offer.

The artifact sub-object snapshots all fields from both the YAML spec and the
live artifact state. Fields with YAML defaults (e.g., `evolution_chance`) that
were omitted in the spec file are filled in by `_apply_defaults` during `begin`.

### 5.5 SeasonFactionState (per-season global faction tracking) — Planned

| Field | Type | Description |
|-------|------|-------------|
| faction_id | string | FK to faction definition |
| season_id | UUID | FK to Season |
| influence | integer | Accumulated value from all sales to this faction |
| artifacts_received | integer | Count of artifacts sold to this faction |

Not yet implemented. Will drive faction dominance, Crier reports, and buyer
context.

### 5.6 ArtifactDisposition (per-sale record) — Planned

| Field | Type | Description |
|-------|------|-------------|
| disposition_id | UUID | Primary key |
| season_id | UUID | FK to Season |
| player_id | UUID | FK to PlayerAccount |
| faction_id | string | Which faction bought it |
| season_day | integer | When the sale occurred |
| value_awarded | integer | Final sale value |
| artifact_snapshot | JSON | Full artifact state at sale time |
| standing_delta | integer | Standing change from this sale |
| influence_delta | integer | Influence added to faction |
| narrative_hooks | JSON | Keys for future Crier/narrative generation |

Not yet implemented. Append-only. Immutable after creation. Survives character
deletion.

### 5.7 SeasonRecord (post-season archive)

| Field | Type | Description |
|-------|------|-------------|
| record_id | UUID | Primary key |
| season_id | UUID | FK to Season |
| player_id | UUID | FK to PlayerAccount |
| final_score | integer | Season-ending score |
| final_scrap | integer | Season-ending scrap |
| rank | integer | Final leaderboard position |
| faction_standing_snapshot | JSON | Standing at season end |
| story_highlights | JSON | Notable dispositions and narrative hooks |
| created_at | timestamp | When finalized |

Created during season finalization, before characters are deleted.

### 5.8 Entity Lifecycle

```
PlayerAccount ─── persists forever ──────────────────────►
       │
       ├── Season 1 ─── SeasonalCharacter ──► deleted ──►
       │                     │
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
3. Then hard-deletion is permitted

---

## 6. Game Mechanics

### 6.1 Artifact Drawing

Artifacts are selected via weighted random selection from the YAML content
pool. Each artifact spec has a `weight` field. Total weight sums across all
specs, and a random roll selects one.

### 6.2 Push Model (Artifact Destabilization)

Each push operation:

1. **Increment push_count**

2. **Instability growth**: `growth = instability_growth_min + random_int(0, instability_growth_max - instability_growth_min)`
   - The random component uses a uniform distribution for the integer range

3. **Stage determination**: `ratio = instability / max_instability`
   - `ratio <= stable_threshold` → "stable"
   - `ratio <= strained_threshold` → "strained"
   - `ratio > strained_threshold` → "unstable"

4. **Collapse check**: `collapse_chance = (ratio²) × 0.95`
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
      - pending_activity cleared (activity row deleted)
     - At most ONE evolution per artifact

6. **Value gain** (if no collapse and no breakthrough):
   - `gain = base_gain_min + random_int(0, base_gain_max - base_gain_min)`
   - `artifact.value += gain`
   - A random signal text is selected from the YAML spec for the current stage

### 6.3 Buyer Offers (Market)

When a player stops (not collapses, not breakthroughs), the Market generates
buyer offers:

1. **Eligibility**: Each faction has an `interested_behaviors` list. A faction
   is eligible if:
   - It has `*` (wildcard interest), OR
   - Any artifact behavior matches any faction interest

2. **Selection**: Up to two factions are selected from the eligible pool via
   weighted random selection. If only one faction is eligible, a single
   offer is generated. Each faction's weight = its `influence` value
   (from faction influence tracking), defaulting to 1 if no influence is
   recorded.

3. **Offer generation**: For each selected faction:
   - `multiplier = faction.base_multiplier` (may be overridden by special
     faction logic, e.g., Faculty's `effective_multiplier` for evolved
     artifacts)
   - `offer_value = floor(artifact.value × multiplier)`
   - An offer text is generated
    - All offers are returned as an array and persisted in the activity row's `offers` column

**Market constraints**:
- Does not mutate state or faction influence
- Does not know about individual player standing
- Influence is passed as a parameter, not read from state directly
- Commission premiums are applied by the controller AFTER Market returns

### 6.4 Sale Effects

When a player sells to a faction (validates the chosen buyer against stored
offers):

1. Add chosen offer's `value` to both `scrap` and `score`
2. Increment `faction_sales[faction_id]` counter
3. Adjust `standing[faction_id]` by +1
4. *(Planned)* Update `SeasonFactionState`: add offer value to faction's
   influence, increment faction's `artifacts_received`
5. *(Planned)* Create `ArtifactDisposition` record with full snapshot
6. Record transcript event
7. Delete activity row, clear `pending_activity_id` FK on character
8. *(Planned)* Optionally return post-sale resolution text (from YAML content,
   tiered by value)

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

### 7.2 Commission System — Planned (Not Yet Implemented)

After a player's second seasonal sale to a faction, that faction "notices" the
player and may issue a commission:

- **Trigger**: `faction_sales[faction_id] == 2` AND no active commission AND
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

- **Premium application**: After Market generates offers, the activity checks
   if the artifact's behaviors intersect with the commission's requested
  behaviors. If so, multiply that faction's offer value by `premium_multiplier`.
  Only that faction's offer is affected; other offers are unchanged.

- **Fulfillment**: Selling to the commission faction while a matching
  commission is active fulfills it — `active_commission` is cleared.

- **Expiry**: Decrements `remaining_attempts` each time the player starts a
  new artifact. At 0, the commission expires and is cleared.

- **Constraints**: At most ONE active commission. No quest-acceptance UI
  required. Player may always ignore the commission. Commission never affects
  push/collapse/breakthrough math.

- **Bot policy**: `commission_seeker` — when a commission is active and a
  matching offer exists, always picks that offer even over higher-value ones.

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

**`on_maintenance` callback** (extension point for day-rollover logic):

This callback is the single place where day-advancement logic lives. It
receives the Maintenance object (`$self`). Planned implementation:

1. Increment `season.day` by 1
2. For every SeasonalCharacter: reset `turns_remaining` to the configured
   daily allowance (e.g., 10)
3. Preserve activity rows — in-progress artifacts survive rollover
4. Update leaderboard (Hall of Fame snapshots)
5. If `season.day > season_length`, emit a warning (season end is manual)

The callback is currently a no-op; the day-rollover logic has not been
wired up yet. The maintenance window infrastructure (timing, route gating,
`in_maintenance` flag) is fully implemented and tested.

**Route gating during maintenance**:

Routes are partitioned into three tiers via Mojolicious `under` bridges:

| Tier | Routes | During Maintenance |
|------|--------|--------------------|
| Public read-only | `GET /`, `/login`, `/logout`, `DELETE /sessions` | Allowed |
| Writes (no auth) | `POST /sessions` | HTTP 503 |
| Authenticated | `GET /player`, `DELETE /player`, `GET /game` | HTTP 503 |

The `is_maintenance` helper checks `$app->maintenance->in_maintenance` and
returns 503 for gated routes.

**Invariants**:
- Controllers NEVER check for or apply daily rollover
- Controllers trust `turns_remaining` as written by the maintenance callback
- The `in_maintenance` flag blocks concurrent writes during the callback
- Login and account creation are rejected during maintenance (503)

### 8.2 Season Start

Admin-triggered. Creates a new Season record with status `active`, day 1.
Season length is a game constant (e.g., 30 days). When a player joins
mid-season, their character is created with full daily turns at the current
season day.

### 8.3 Season End (Finalization)

Admin-triggered. MUST execute in this exact order:

1. Compute final leaderboard rank for each character
2. For each SeasonalCharacter:
   a. Collect final stats (score, scrap, standing, faction_sales)
   b. Collect significant ArtifactDisposition records
   c. Build SeasonRecord (score, scrap, rank, standing snapshot, disposition
      summaries, narrative hooks)
   d. Store SeasonRecord (append-only, survives deletion)
3. Verify ALL SeasonRecords are stored successfully
4. Delete ALL SeasonalCharacter rows for this season
5. Clear SeasonFactionState
6. Set Season.status = "archived"

Hard-deletion of characters is ONLY permitted after this formal sequence.
Pending activities are discarded at season end — unresolved artifacts are
forfeit.

---

## 9. Activity System

Every expedition (Prospecting, future Contracts, Encounters) is a state machine
and a persisted entity. Activity extends `MagicMountain::Model` — the same
JSON-file CRUD base as Account, Character, and Season. Activity state lives in
`activities.json`, linked to characters via `pending_activity_id`.

### 9.1 Activity Base Class

`MagicMountain::Activity` provides the persistence layer, state-machine skeleton,
content loading, and column accessors. Subclasses declare their legal transitions
and implement handler methods.

**Two categories of fields on the same object:**

| Category | Mechanism | Examples |
|----------|-----------|----------|
| Persisted | Declared in `columns`, accessed via `getCol`/`setCol`, survives `save()` | `char_id`, `type`, `phase`, `artifact`, `offers` |
| Ephemeral | Regular Mojo `has` attributes, set at construction, shared across instances | `transitions`, `app`, `content_filename`, `content_data`, `log` |

**Column accessors:** `phase`, `artifact`, and `offers` have convenience
accessor methods that bridge Mojo attribute syntax (`$self->phase('processing')`)
to column storage (`getCol`/`setCol` — reading/writing `$self->row`).

**Construction overrides:** The base class overrides `get()` and `create()` from
Model. After calling `SUPER` (Model's versions which pass `file`/`log`/`table`/`row`
to `new()`), they propagate ephemeral attributes (`transitions`, `app`, `content_data`)
from the global instance to the new instance. This eliminates the need for separate
factory methods or `_propagate` helpers.

**Dispatch:**

```perl
sub dispatch ($self, $char, $action, %params) {
    die "illegal transition: $self->{phase} -> $action"
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
5. Mutate character fields directly (e.g. `$char->{scrap} += $value`)
6. Set phase directly: `$self->phase('processing')`
7. Return `{ view => {...} }` — the controller pipes `view` directly to the template

```perl
{
    view => {
        ok     => 1,
        result => 'push',
        artifact => { stage => 'strained', signal => 'It groans...', value => 24 },
        player   => { turns_remaining => 6, scrap => 10, score => 10 },
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
└────────────────────┘             │ artifact: { id, value,…}│
                                   │ offers: null            │
                                   └─────────────────────────┘
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

### 9.5 Prospecting Example

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
    { idle => ['begin'], processing => ['push', 'stop'], awaiting_buyer => ['sell'] }
};

sub create ($self, %params) {
    $params{type}  //= 'prospecting';
    $params{phase} //= 'idle';
    return $self->SUPER::create(%params);
}
```

### 9.6 Bots

Bots call the same `dispatch()` method with the same character model.
The transition table is checked identically — a bot cannot exploit HTTP
endpoint knowledge because the state machine lives in the activity, not
in the route.

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
        sub { $_->{account_id} eq $player_id }
    ) };
    return $self->render(json => { ok => 0, error => 'No character' }, status => 404)
        unless $char_model;

    my $p   = $self->app->prospecting;
    my $row = $char_model->row;
    my $id  = $row->{pending_activity_id};

    my $activity = $id
        ? $p->get($id)
        : $p->create(char_id => $row->{id});

    my $result = $activity->dispatch($row, $action, %params);

    if ($activity->phase eq 'idle') {
        $p->delete($activity->getCol('id'));
        $char_model->setCol('pending_activity_id', undef);
    } else {
        $activity->save;
        $char_model->setCol('pending_activity_id', $activity->getCol('id'));
    }
    $char_model->save;

    $self->render(json => $result->{view});
}
```

The controller loads or creates the activity row via the global instance,
dispatches, saves the activity row, and saves the character. It never inspects
activity row internals or checks phases.

### 10.2 Controller Inventory

| Controller | Actions | Purpose |
|-----------|---------|---------|
| Root | index | Gateway redirect (/ → /login or /game) |
| Sessions | login_form, create, destroy, logout | Authentication |
| Player | show, destroy | Current player JSON; delete account |
| Game | show | Game state page |
| Artifact | begin, push, stop | Prospecting lifecycle |
| Sale | create | Choose faction buyer |
| Leaderboard | index | Player rankings |

### 10.3 What Controllers Do NOT Do

- Do NOT check `last_refreshed_day` or apply daily rollover
- Do NOT advance the season clock or refresh turns
- Do NOT construct characters (created by the join-season flow or maintenance)
- Do NOT create accounts (that's Sessions)
- Do NOT validate activity phases (the activity base class does this)
- Do NOT call persistence methods on models (the activity does this)
- Do NOT generate offers or apply sale effects (Market and the activity handle this)
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
  prospecting.yml                 # All artifact definitions (one file per activity type)
  text/
    daily_messages.yml
    season_opening.yml
    faction_resolutions.yml       (future)
    commission_triggers.yml       (future)
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
  sale:                          # Post-sale text by value tier
    low:
      - A curiosity for junk collectors.
    medium:
      - A functional thermal cell...
    high:
      - An intact energy chassis...
```

### 12.3 Text Content Shape

**daily_messages.yml**: Array under `daily_messages` key. Shown on state
requests, cycled by season day or random.

**season_opening.yml**: Array under `season_opening` key. Shown on day 1
of each season.

**faction_resolutions.yml** (future): Per-faction post-sale resolution text,
tiered by value (low/medium/high). Pure narrative, no mechanical effect.

**commission_triggers.yml** (future): Per-faction commission definitions
(behaviors, premium_multiplier, trigger_text).

### 12.4 Content Loading

The app class sets `content_filename` to the full path of the activity's YAML
file (e.g. `$self->home . '/content/prospecting.yml'`). `load_content` is called
once at startup on the global instance. The parsed data is stored in `content_data`
and automatically propagated to per-request activity instances via the overridden
`get()`/`create()` methods.

Adding a new artifact requires editing the relevant YAML file — no code changes,
no manual registration.

---

## 13. API Endpoints

| Method | Path | Controller#Action | Purpose |
|--------|------|-------------------|---------|
| GET | `/` | `Root#index` | Gateway redirect |
| GET | `/login` | `Sessions#login_form` | Login form |
| POST | `/sessions` | `Sessions#create` | Login or auto-create player |
| DELETE | `/sessions` | `Sessions#destroy` | Logout (API, JSON) |
| GET | `/logout` | `Sessions#logout` | Logout (browser, redirects) |
| GET | `/player` | `Player#show` | Current player JSON |
| DELETE | `/player` | `Player#destroy` | Delete account (cascades: character, sessions, audit log) |
| GET | `/game` | `Game#show` | Game state page |
| POST | `/artifact/begin` | `Artifact#begin` | Start new artifact (consumes turn) |
| POST | `/artifact/push` | `Artifact#push` | Destabilize artifact |
| POST | `/artifact/stop` | `Artifact#stop` | Halt, generate buyer offers |
| POST | `/sale` | `Sale#create` | Choose buyer, award value |
| GET | `/leaderboard` | `Leaderboard#index` | Player rankings |

### 13.1 Controller Action Contracts

**Artifact#begin**: Requires `turns_remaining > 0` and no active activity
(`pending_activity_id` null). Draws random artifact from Content pool. Creates
a new activity row with phase `processing`. Decrements `turns_remaining`.

**Artifact#push**: Requires activity `type == "prospecting"` and
`phase == "processing"`. Delegates to `Activity::Prospecting::push()`.
Possible outcomes: normal (updated artifact), collapse (row deleted),
breakthrough (cashed out, row deleted).

**Artifact#stop**: Requires activity `phase == "processing"`. Generates
offers via Market (passing artifact + faction influence). Sets phase to
`"awaiting_buyer"`. Returns offers.

**Sale#create**: Requires activity `phase == "awaiting_buyer"`.
Receives `faction_id` in request body. Validates against stored offers.
Applies sale effects (scrap, score, standing, faction_sales). Deletes
activity row.

### 13.2 Response Shape for Game State

```json
{
  "ok": true,
  "player": {
    "name": "Joe",
    "turns_remaining": 7,
    "scrap": 42,
    "score": 42,
    "faction_sales": { "syndicate": 2, "libremount": 1 }
  },
  "artifact": {
    "id": "thermal_box_001",
    "stage": "strained",
    "value": 18,
    "signal": "The box grows uncomfortably hot...",
    "intro": "The box is warm to the touch..."
  },
  "pending_sale": {
    "offers": [
      { "faction_id": "syndicate", "faction_name": "The Syndicate",
        "value": 20, "text": "...", "disposition": "pragmatic" }
    ]
  },
  "season": { "day": 5, "total_days": 30 },
  "world_message": "The air tastes faintly of ozone...",
  "season_opening": null
}
```

`artifact` is present only when prospecting is in `processing` phase.
`pending_sale` is present only in `awaiting_buyer` phase.
Both are null when idle.

---

## 14. Bot Simulation

Bots are automated players that invoke the same service classes as the web
controllers. The simulate CLI command reads artifact content, iterates through
a population of bots, and calls `Activity::Prospecting`, `Market`, and
`SeasonalCharacter` mutators directly — producing game outcomes identical to
human play.

### 14.1 Push Policies

| Policy | Parameters | Behavior |
|--------|------------|----------|
| `fixed_pushes` | `max` (default 3) | Push exactly N times, then stop |
| `instability_cap` | `max` (default 5) | Push until instability exceeds cap |
| `stage_guard` | `stop_at` (default "unstable") | Push until target stage reached |
| `greed` | `prob` (default 0.7) | Push with probability P each time |
| `value_target` | `min` (default 20) | Push until value exceeds target |
| `composite` | `op` ("and"/"or"), `policies` (sub-policy array) | Combine multiple policies |

### 14.2 Buyer Policies

| Policy | Behavior |
|--------|----------|
| `highest_offer` | Pick the numerically highest offer value |
| `syndicate_loyalist` | Always pick Syndicate if present, otherwise highest |
| `libremount_loyalist` | Always pick LibreMount if present, otherwise highest |
| `faculty_anomaly_hunter` | Pick Faculty for evolved artifacts, otherwise highest |
| `mixed_opportunist` | 50% random choice, 50% highest offer |
| `commission_seeker` | (future) Pick commission-matching offer if active |

---

## 15. Transcript

JSONL (JSON Lines) file for recording game events. Each event is one JSON
object per line. Used for simulation analysis, balance evaluation, and
diagnostics. Events include: `artifact_start`, `push`, `collapse`,
`breakthrough`, `stop`, `sell`, and future `commission_triggered`,
`commission_fulfilled`, `commission_expired`.

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
  human harm.

---

## 17. Architecture Invariants (Do Not Violate)

### Persistence

1. **Models own their own persistence.** `Model::Character`, `Model::Account`,
   etc. provide `save()`, `create()`, `find()`. No separate State or
   persistence coordinator layer wraps them.

2. **Models must not contain game logic.** A model's columns and CRUD
   operations are pure data access. Artifact math, faction rules, and
   transition validation live in activities and services.

### Activities

3. **Activities are persisted entities, not transient services.** They extend
   `MagicMountain::Model` and store state in `activities.json`. Phase, artifact,
   offers, and type are persisted columns. Transitions, app, content_data, and
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

### Market

7. **Market generates offers only.** It never applies sale effects or mutates
   persistent state. Influence is passed as an input snapshot and never
   mutated.

### Offers & Sales

8. **Once buyer offers are generated, they are persisted** in the activity
   row's `offers` column and must not be rerolled at selection time. The sell
   action validates the submitted faction against stored offers.

9. **Starting a daily activity consumes one daily event.** Resolving its later
   steps does not.

### Rollover & Maintenance

10. **Only the on_maintenance callback (driven by the Maintenance IOLoop timer)
    advances the season clock or refreshes turns.** Controllers never check
    for or apply daily rollover.

11. **Active activity rows survive day rollover** and are discarded only at
    season finalization.

### Characters & Deletion

12. **Seasonal characters may be deleted only after** final SeasonRecord
    creation succeeds.

### Gameplay Invariants

13. **Faction standing and influence must not alter artifact push/collapse
    physics.** Market offerings may vary, but artifact behavior does not.

14. **Score is cumulative seasonal leaderboard value and never decreases.**
    Scrap is spendable seasonal currency that may decrease through future
    systems.

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

20. **Narrative emissions are not activities.** They do not consume turns.

### Transcript

21. **The app class owns transcript lifecycle.** It opens a transcript context
    on each request (session, player, endpoint, timestamp). Activities enrich
    it with game events. The app closes it (duration, outcome). No single
    module is the sole transcript writer.

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

The new codebase (`lib/`) is a ground-up rebuild. The original working
implementation lives in `original/` as a reference.

### 19.1 Implemented

| Feature | Module(s) | Notes |
|---------|-----------|-------|
| **Model persistence layer** | `Model.pm`, `Model::Account`, `Model::Character`, `Model::Season`, `Model::HallOfFame`, `Model::Session`, `Model::AuditLog` | JSON file CRUD, UUID, atomic write-via-temp-file |
| **Routing gateway** | `Controller::Root` | `GET /` redirect |
| **Login flow** | `Controller::Sessions` | Auto-creates accounts on first login |
| **Player info** | `Controller::Player` | `GET /player` JSON or 401 |
| **Game page** | `Controller::Game`, `templates/game/show.html.ep` | Authenticated home with season info |
| **Session management** | `Model::Session`, `current_player` helper | Configurable inactivity timeout |
| **CLI commands** | `Command::create_account`, `Command::list_accounts`, `Command::delete_account`, `Command::disable_account` | Account lifecycle |
| **Layout** | `templates/layouts/default.html.ep` | Bootstrap 5.3 CDN wrapper |
| **Day maintenance** | `Maintenance.pm` | IOLoop timer, `in_maintenance` flag, route gating, `on_maintenance` extension point. Rollover logic not wired yet. |
| **Audit logging** | `Model::AuditLog` | JSONL login/logout/account events |

### 19.2 Planned (Not Yet Implemented)

| Feature | Status | Notes |
|---------|--------|-------|
| Activity base class | Not started | State-machine transition enforcement, `dispatch()` |
| Content system (YAML artifacts) | In progress | Artifact definitions in `content/prospecting.yml`, loaded via Activity::load_content |
| Activity::Prospecting | In progress | Push/collapse/breakthrough math implemented; stop/sell stubbed (Market integration pending) |
| Market (buyer offers) | Not started | Faction-based offer generation |
| SeasonalCharacter wrapper | Not started | Invariant-preserving character mutations |
| Model::Character expansion | In progress | Added `pending_activity_id` FK column; `scrap`, `turns_remaining` still via TestCharacter hashref |
| Faction system | Not started | FactionRegistry, YAML-driven faction config |
| advance-day rollover logic | Not started | The `on_maintenance` callback in Maintenance.pm is currently a no-op. Day increment, turn refresh, and leaderboard snapshot still need to be implemented inside that callback. |
| Artifact/Sale controllers | Not started | Game action HTTP endpoints |
| Bot simulation | Planned | Automated players using same service classes |
| Transcript (event recording) | Planned | JSONL for simulation and balance analysis |
| Leaderboard | Planned | Player rankings |
| ArtifactDisposition records | Planned | Append-only immutable sale records |
| SeasonFactionState tracking | Planned | Per-faction influence/artifacts tracking |
| Commission system | Planned | Faction notices, active commissions, expiry |
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
   (phase, artifact, offers) and ephemeral attributes (transitions, content_data).
   One global instance per activity type holds the persistence table and loaded
   content; per-request rows are created/loaded via Model's `get()`/`create()`.

4. **In-process maintenance timer over cron-triggered rollover**: A
   `Mojo::IOLoop` recurring timer drives the `Maintenance.pm` state machine.
   The `in_maintenance` flag gates write routes during the maintenance
   window, and the `on_maintenance` callback is the single extension point
   for all day-rollover logic. This eliminates rollover checks from every
   HTTP request, simplifies controllers, keeps maintenance self-contained
   (no external cron), and provides a natural lock point for bulk updates.

5. **Admin-triggered season end**: Never automatic. The maintenance callback
   may warn when configured season length is reached but does not
   auto-finalize.

6. **Collapse = zero salvage**: No partial recovery on collapse. This is the
   game's core risk; partial salvage would weaken the push-your-luck tension.

7. **At most one evolution per artifact**: `has_evolved` flag. No artifact
   can breakthrough more than once.

8. **Offers never rerolled**: Once generated at `stop`, offers are frozen in
    the activity row's `offers` column. The `sell` action matches by faction_id,
    not by regenerating. This prevents save-scumming and ensures offer data
    integrity.

9. **Score vs Scrap separation**: Score is the leaderboard metric (never
   decreases). Scrap is currency (future spendable). Currently they track
   together, but the separate fields enable future mechanics (purchases,
   bribes, commissions) that spend scrap without affecting score.

10. **Commission premiums applied by activity, not Market**: Market knows
    nothing about player state. The activity post-processes Market output to
    apply commission premiums. This keeps Market pure.

11. **SeasonalCharacter deletion after formal SeasonRecord creation**: The
    deletion is safe because the meaningful history has already been archived.
