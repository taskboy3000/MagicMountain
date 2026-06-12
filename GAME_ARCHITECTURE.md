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

Controllers handle HTTP requests from human players. Each action reads the
player's character state, validates the request, delegates computation to
stateless service classes, and writes the result. Controllers own the
read-modify-write cycle for their specific action — there is no intermediate
coordinator.

```
Browser → Mojo route → Controller action
                          │
                          ├── State: get_character($player_id)
                          ├── Activity::Prospecting: handle($char, $action, %params)
                          ├── Market: generate_offers($artifact, $influence)
                          ├── SeasonalCharacter: mutators
                          ├── Transcript: record($event)
                          └── State: put_character($player_id, $char_data)
```

Controllers are the entry points. They do not check for day rollover, advance
the clock, or refresh turns — they trust the state as written.

### 3.2 Phase 2: Daily Maintenance (Cron)

A CLI command (`advance-day`) runs once per game-day, triggered by cron or a
scheduler. It locks state, advances the clock, refreshes all player turns, and
exits. No HTTP requests are served during maintenance (logins are rejected).

```
Cron → perl script/mountain advance-day
         │
         ├── Lock state
         ├── Increment season.day
         ├── For each character: reset turns_remaining
         ├── Update leaderboard
         ├── Check for season end
         └── Unlock, exit
```

**Maintenance window**: The server may optionally reject logins during the
brief maintenance window. The lock on the state file naturally serializes
access even without an explicit gate.

### 3.3 Why Not an Engine?

A central "Engine" coordinator class was considered and rejected because:

- Mojolicious already routes HTTP requests to controllers — adding another
  dispatch layer creates indirection without value.
- Daily maintenance is a system-level concern that should not live inside an
  HTTP request/response cycle.
- With file-level locking (flock), atomicity is guaranteed at the persistence
  layer — no coordinator needed to enforce it.
- Each controller action is specific to one game operation. There is no
  generic "handle_action" dispatch to build.

---

## 4. Module Boundary Table

Each module has strict constraints on what it may and must never hold.

| Module | May Hold | Must NEVER Hold |
|--------|----------|-----------------|
| **Controller::*** | App reference, State, Content, Market, Transcript | — |
| **Activity::*** (any activity) | App reference (only for `content` and `log` trampolines) | State, Transcript, AccountStore, Market |
| **Market** (offer generator) | List of Faction objects | State, Transcript, AccountStore |
| **SeasonalCharacter** (player state wrapper) | Internal data hashref, player_id | State (must not know about persistence), Transcript, Market |
| **State** (persistence) | File path, internal data hashref | Content, Transcript, game defaults |
| **AccountStore** (account persistence) | File path | State, Transcript, Content |
| **SessionStore** (session persistence) | File path | State, Transcript, Content, game rules |
| **Content** (YAML loader) | Directory path, parsed YAML data | State, Transcript, game rules |
| **Transcript** (event recorder) | File handle, session ID, sequence counter | State, game rules, AccountStore |
| **Faction** (buyer definition) | ID, name, multiplier, interests, disposition | State, Transcript, player data |
| **Bot** (automated player) | Policy name, parameters | Direct persistence (must use same service classes as controllers) |

### Constructor Checklist for Activity Subclasses

An Activity subclass receives ONLY these from its constructor:
- **app** — application reference (for YAML content and logging only)
- Nothing else. NO state. NO transcript. NO account_store. NO market.

Context data for `handle()` calls (faction influence values, pre-computed
offers) arrives as explicit parameters. These are values, not service objects.

### Controller Responsibility

Controllers coordinate the read-modify-write cycle for their specific action:

1. Read character via `State::get_character`
2. Wrap character in `SeasonalCharacter` for invariant enforcement
3. Delegate to Activity for pure computation
4. Generate offers via Market (for stop action)
5. Apply sale effects via SeasonalCharacter mutators
6. Record transcript events
7. Write character via `State::put_character`

No controller checks for day rollover. No controller refreshes turns. The
state is trusted as-is. The cron job owns all time-related mutations.

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
| pending_activity | object or null | Current activity state (see below) |
| current_location | string | Current location ID in the location graph (default: `camp`) |

> **Note on `last_refreshed_day`**: This field existed in the original
> "lazy rollover" design where turns were refreshed on next player action.
> The cron-based maintenance design refreshes all turns during the daily
> maintenance window, so this field is no longer needed. Controllers trust
> `turns_remaining` as written.

**Invariants enforced by SeasonalCharacter wrapper:**
- `turns_remaining` cannot go below zero
- `scrap` must be non-negative
- `pending_activity` must have a `type` field if set
- `score` never decreases
- Attempting to consume a daily event when turns are zero is a hard error

**Property distinction:**
- `score` = cumulative seasonal leaderboard value, never decreases
- `scrap` = spendable seasonal currency, may decrease through future systems

### 5.4 pending_activity (state machine container)

This single field replaces all separate `current_artifact`, `pending_sale`,
and activity-specific fields. Shape depends on phase:

**Idle:**
```
null
```

**Prospecting in progress:**
```
{
  "type": "prospecting",
  "phase": "processing",
  "artifact": {
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
}
```

**Awaiting buyer:**
```
{
  "type": "prospecting",
  "phase": "awaiting_buyer",
  "artifact": { ...same shape... },
  "offers": [
    {
      "offer_id": "offer_001",
      "faction_id": "syndicate",
      "faction_name": "The Syndicate",
      "value": 24,
      "text": "A broker tags it for resale.",
      "disposition": "pragmatic"
    },
    {
      "offer_id": "offer_002",
      "faction_id": "faculty",
      "faction_name": "The Faculty",
      "value": 29,
      "text": "A scholar notes the signal.",
      "disposition": "scholarly"
    }
  ]
}
```

**Critical rule**: Once offers are generated at stop time, they are persisted
in `pending_activity` and MUST NOT be rerolled at sell time. The sell action
validates the submitted faction against stored offers and returns the exact
stored offer.

The artifact sub-object within `pending_activity` snapshots all fields from
both the YAML spec and the live artifact state. Fields present in the YAML
spec are always included; fields with YAML defaults (e.g., `evolution_chance`)
that were omitted in the spec file are filled in by the artifact factory.

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
     pending_activity clears

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
     - pending_activity clears
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
   - All offers are returned as an array and persisted in `pending_activity`

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
7. Clear `pending_activity`
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

- **Premium application**: After Market generates offers, the controller checks
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

### 8.1 Daily Maintenance (Cron-Triggered)

The `advance-day` CLI command runs once per game-day. It is the ONLY code
path that advances the season clock or refreshes player turns.

**Execution**:
```
perl script/mountain advance-day
```

**What it does**:
1. Acquire lock on state file
2. Increment `season.day` by 1
3. For every SeasonalCharacter:
   - Reset `turns_remaining` to the configured daily allowance (e.g., 10)
   - Preserve `pending_activity` — in-progress artifacts survive rollover
4. Update leaderboard
5. If `season.day > season_length`, emit a warning (season end is manual)
6. Release lock, exit

**Invariants**:
- Controllers NEVER check for or apply daily rollover
- Controllers trust `turns_remaining` as written by maintenance
- During maintenance, the state lock prevents concurrent writes
- Login may be disabled during maintenance (optional gate)

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

## 9. Request Handling (Controllers)

Controllers are Mojolicious controller classes. They handle one specific
game action each and own the full read-modify-write cycle for that action.

### 9.1 Controller Structure

Each controller action follows this pattern:

```perl
sub action_name ($self) {
    my $player_id = $self->current_player;
    my $state = $self->app->state;

    $state->with_transaction(sub {
        # 1. Load character
        my $char_data = $state->get_character($player_id);
        die "No character" unless $char_data;
        my $char = SeasonalCharacter->new(data => $char_data);

        # 2. Validate state (e.g., check pending_activity phase)

        # 3. Delegate to service classes
        my $result = $self->app->prospecting->handle($char, $action, %params);

        # 4. Apply side effects (offer generation, sale effects)

        # 5. Record transcript
        if ($result->{transcript_event}) {
            $self->app->transcript->record($result->{transcript_event});
        }

        # 6. Persist
        $state->put_character($player_id, $char->data);

        return $result;
    });
}
```

### 9.2 Controller Inventory

| Controller | Actions | Purpose |
|-----------|---------|---------|
| Root | index | Gateway redirect (/ → /login or /game) |
| Sessions | login_form, create, destroy, logout | Authentication |
| Player | show | Current player JSON |
| Game | show | Game state page |
| Artifact | begin, push, stop | Prospecting lifecycle |
| Sale | create | Choose faction buyer |
| Leaderboard | index | Player rankings |

### 9.3 What Controllers Do NOT Do

- Do NOT check `last_refreshed_day` or apply daily rollover
- Do NOT advance the season clock
- Do NOT refresh turns
- Do NOT construct characters (characters are created by the join-season flow
  or the maintenance command for new players joining mid-season)
- Do NOT create accounts (that's Sessions)

---

## 10. Account & Login Flow

1. Client submits display name to login endpoint (`POST /sessions`)
2. AccountStore looks up name; if not found, creates a new PlayerAccount
   (UUID + display_name + timestamp) — accounts are auto-created on first login
3. A server-side session record is persisted (player_id, last_active) with
   configurable inactivity timeout (default 60 minutes, set via
   `session_timeout_minutes` in `magic_mountain.yml`)
4. Mojolicious session cookie stores `playerId`
5. When a player first accesses the game, a SeasonalCharacter is created for
   them (either by the join-season flow or the next maintenance cycle)
6. Controllers access character data directly via State — no intermediate
   coordinator

Display names must be unique.

### 10.1 Session Lifecycle

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

## 11. Content System (YAML-Driven)

### 11.1 Directory Structure

```
content/
  artifacts/
    thermal_box.yml
    black_canister.yml
    rusted_core.yml
    crystal_chime.yml
    wire_bundle.yml
    (any number of *.yml files — auto-discovered)
  text/
    daily_messages.yml
    season_opening.yml
    faction_resolutions.yml       (future)
    commission_triggers.yml       (future)
```

### 11.2 Artifact Definition Shape

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

### 11.3 Text Content Shape

**daily_messages.yml**: Array under `daily_messages` key. Shown on state
requests, cycled by season day or random.

**season_opening.yml**: Array under `season_opening` key. Shown on day 1
of each season.

**faction_resolutions.yml** (future): Per-faction post-sale resolution text,
tiered by value (low/medium/high). Pure narrative, no mechanical effect.

**commission_triggers.yml** (future): Per-faction commission definitions
(behaviors, premium_multiplier, trigger_text).

### 11.4 Content Loading

All YAML files in the content directory tree are loaded at application
startup. Adding a new artifact or text file requires only placing a `.yml`
file in the correct directory — no code changes, no manual registration.

---

## 12. API Endpoints

| Method | Path | Controller#Action | Purpose |
|--------|------|-------------------|---------|
| GET | `/` | `Root#index` | Gateway redirect |
| GET | `/login` | `Sessions#login_form` | Login form |
| POST | `/sessions` | `Sessions#create` | Login or auto-create player |
| DELETE | `/sessions` | `Sessions#destroy` | Logout (API, JSON) |
| GET | `/logout` | `Sessions#logout` | Logout (browser, redirects) |
| GET | `/player` | `Player#show` | Current player JSON |
| GET | `/game` | `Game#show` | Game state page |
| POST | `/artifact/begin` | `Artifact#begin` | Start new artifact (consumes turn) |
| POST | `/artifact/push` | `Artifact#push` | Destabilize artifact |
| POST | `/artifact/stop` | `Artifact#stop` | Halt, generate buyer offers |
| POST | `/sale` | `Sale#create` | Choose buyer, award value |
| GET | `/leaderboard` | `Leaderboard#index` | Player rankings |

### 12.1 Controller Action Contracts

**Artifact#begin**: Requires `turns_remaining > 0` and `pending_activity` null.
Draws random artifact from Content pool. Sets `pending_activity` to
prospecting.processing. Decrements `turns_remaining`.

**Artifact#push**: Requires `pending_activity.type == "prospecting"` and
`phase == "processing"`. Delegates to `Activity::Prospecting::handle($char,
'push')`. Possible outcomes: normal (updated artifact), collapse (cleared),
breakthrough (cashed out).

**Artifact#stop**: Requires `pending_activity.phase == "processing"`. Generates
offers via Market (passing artifact + faction influence). Sets phase to
"awaiting_buyer". Returns offers.

**Sale#create**: Requires `pending_activity.phase == "awaiting_buyer"`.
Receives `faction_id` in request body. Validates against stored offers.
Applies sale effects (scrap, score, standing, faction_sales). Clears
pending_activity.

### 12.2 Response Shape for Game State

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

## 13. Bot Simulation

Bots are automated players that invoke the same service classes as the web
controllers. The simulate CLI command reads artifact content, iterates through
a population of bots, and calls `Activity::Prospecting`, `Market`, and
`SeasonalCharacter` mutators directly — producing game outcomes identical to
human play.

### 13.1 Push Policies

| Policy | Parameters | Behavior |
|--------|------------|----------|
| `fixed_pushes` | `max` (default 3) | Push exactly N times, then stop |
| `instability_cap` | `max` (default 5) | Push until instability exceeds cap |
| `stage_guard` | `stop_at` (default "unstable") | Push until target stage reached |
| `greed` | `prob` (default 0.7) | Push with probability P each time |
| `value_target` | `min` (default 20) | Push until value exceeds target |
| `composite` | `op` ("and"/"or"), `policies` (sub-policy array) | Combine multiple policies |

### 13.2 Buyer Policies

| Policy | Behavior |
|--------|----------|
| `highest_offer` | Pick the numerically highest offer value |
| `syndicate_loyalist` | Always pick Syndicate if present, otherwise highest |
| `libremount_loyalist` | Always pick LibreMount if present, otherwise highest |
| `faculty_anomaly_hunter` | Pick Faculty for evolved artifacts, otherwise highest |
| `mixed_opportunist` | 50% random choice, 50% highest offer |
| `commission_seeker` | (future) Pick commission-matching offer if active |

---

## 14. Transcript

JSONL (JSON Lines) file for recording game events. Each event is one JSON
object per line. Used for simulation analysis, balance evaluation, and
diagnostics. Events include: `artifact_start`, `push`, `collapse`,
`breakthrough`, `stop`, `sell`, and future `commission_triggered`,
`commission_fulfilled`, `commission_expired`.

Transcript recording is the controller's responsibility (or a shared helper
used by controllers). Activity classes return `transcript_event` data in their
results; the controller records it. Activities never hold a transcript
reference.

---

## 15. Narrative Constraints

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

## 16. Architecture Invariants (Do Not Violate)

### Persistence

1. **State must not create characters or assign gameplay defaults.**
   Characters are constructed by controllers or the maintenance command.
   State only stores and retrieves.

2. **State must not reference factions, artifacts, or any game concept by
   name.** It is a pure key-value store.

### Activities

3. **Activities must not save state, apply rollover, create accounts, or
   update faction influence.** They return result hashrefs; the caller
   (controller or maintenance command) persists.

4. **Activities receive ONLY an app reference** (for content and log). Context
   data arrives as parameters to `handle()`. State, Transcript, and
   AccountStore are structurally unreachable from activity code.

### Market

5. **Market generates offers only.** It never applies sale effects or mutates
   persistent state. Influence is passed as an input snapshot and never
   mutated.

### Offers & Sales

6. **Once buyer offers are generated, they are persisted** and must not be
   rerolled at selection time. The sale action validates the submitted faction
   against stored offers.

7. **Starting a daily activity consumes one daily event.** Resolving its later
   steps does not.

### Rollover & Maintenance

8. **Only the advance-day CLI command advances the season clock or refreshes
   turns.** Controllers never check for or apply daily rollover.

9. **Pending activity survives day rollover** and is discarded only at
   season finalization.

### Characters & Deletion

10. **Seasonal characters may be deleted only after** final SeasonRecord
    creation succeeds.

### Gameplay Invariants

11. **Faction standing and influence must not alter artifact push/collapse
    physics.** Market offerings may vary, but artifact behavior does not.

12. **Score is cumulative seasonal leaderboard value and never decreases.**
    Scrap is spendable seasonal currency that may decrease through future
    systems.

13. **Collapse = zero salvage.** No partial recovery. This is the game's core
    risk.

14. **At most one evolution per artifact.** `has_evolved` flag prevents
    re-triggering.

### Accounts & Sessions

15. **Display names must be unique.** Login creates accounts; controllers
    never do.

16. **Session timeout is configurable and enforced server-side.** SessionStore
    tracks `last_active` per player. Expired sessions are cleaned up lazily.

### Content & Factions

17. **Faction definitions are data, not code.** FactionRegistry loads YAML.
    Subclass behavior is an exception, not the pattern.

18. **Narrative emissions are not activities.** They do not consume turns.

---

## 17. Activity Discovery (Dynamic Registration)

New activity types are discovered at startup by scanning the Activity
directory. Any class in that namespace is automatically loaded and registered
by its `name()` (lowercased short class name). Adding a new activity type is a
single-file operation — no manual registration, no wiring changes.

The activity registry lives on the app instance (`$app->activities`) and is
available to controllers at request time.

---

## 18. Implementation Status (New Codebase)

The new codebase (`lib/`) is a ground-up rebuild. The original working
implementation lives in `original/` as a reference.

### 18.1 Implemented

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
| **Audit logging** | `Model::AuditLog` | JSONL login/logout/account events |

### 18.2 Planned (Not Yet Implemented)

| Feature | Status | Notes |
|---------|--------|-------|
| State (character persistence) | Not started | Atomic read-write with flock, `with_transaction` |
| Content system (YAML artifacts) | Not started | YAML-driven artifact/text/faction definitions |
| Activity::Prospecting | Not started | Push/collapse/breakthrough math |
| Market (buyer offers) | Not started | Faction-based offer generation |
| SeasonalCharacter wrapper | Not started | Invariant-preserving character mutations |
| Faction system | Not started | FactionRegistry, YAML-driven faction config |
| advance-day CLI command | Not started | Cron-triggered daily maintenance |
| Artifact/Sale controllers | Not started | Game action HTTP endpoints |
| Bot simulation | Planned | Automated players using same service classes |
| Transcript (event recording) | Planned | JSONL for simulation analysis |
| Leaderboard | Planned | Player rankings |
| ArtifactDisposition records | Planned | Append-only immutable sale records |
| SeasonFactionState tracking | Planned | Per-faction influence/artifacts tracking |
| Commission system | Planned | Faction notices, active commissions, expiry |
| MariaDB migration | Future | Replace JSON file persistence |

---

## 19. Key Design Decisions (Rationale Record)

1. **Two-phase architecture over central coordinator**: Player actions and
   daily maintenance are different concerns with different callers (HTTP vs
   cron). Separating them eliminates an unnecessary dispatch layer and makes
   each phase simpler to test and reason about.

2. **Single pending_activity field** over parallel current_artifact/pending_sale
   fields: Only one interaction can be in progress. A single container prevents
   inconsistent state.

3. **Activities are stateless singletons**: One instance per activity type,
   constructed at startup, reused for all requests. Activities do pure
   computation on passed data — no per-request construction.

4. **Cron-triggered rollover** over lazy rollover: The advance-day command
   refreshes all player turns in one batch during a maintenance window. This
   eliminates rollover checks from every HTTP request, simplifies controllers,
   and provides a natural lock point for bulk updates. Login may be disabled
   during the brief maintenance window.

5. **Admin-triggered season end**: Never automatic. The advance-day command
   may warn when configured season length is reached but does not
   auto-finalize.

6. **Collapse = zero salvage**: No partial recovery on collapse. This is the
   game's core risk; partial salvage would weaken the push-your-luck tension.

7. **At most one evolution per artifact**: `has_evolved` flag. No artifact
   can breakthrough more than once.

8. **Offers never rerolled**: Once generated at `stop`, offers are frozen in
   `pending_activity`. The `sell` action matches by faction_id, not by
   regenerating. This prevents save-scumming and ensures offer data integrity.

9. **Score vs Scrap separation**: Score is the leaderboard metric (never
   decreases). Scrap is currency (future spendable). Currently they track
   together, but the separate fields enable future mechanics (purchases,
   bribes, commissions) that spend scrap without affecting score.

10. **Commission premiums applied by controller, not Market**: Market knows
    nothing about player state. The controller post-processes Market output to
    apply commission premiums. This keeps Market pure.

11. **SeasonalCharacter deletion after formal SeasonRecord creation**: The
    deletion is safe because the meaningful history has already been archived.
