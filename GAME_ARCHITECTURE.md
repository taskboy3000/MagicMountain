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

### 1.1 Device-Fiction UI

The entire UI is presented as a fictional in-universe device: the **ProspectBoy 3000 (PB3K)**, a rugged field PDA recovered from the old world. Every screen, panel, and interaction is framed as a function of this device — there is no "game menu" or omniscient interface. The player does not look at the game world through a window; they interact with it through the PB3K's applications, sensors, and communication protocols.

This constraint governs all UI design and content writing:
- **Templates** render PB3K screens (scan panels, cert store, registry entries), not game UI widgets.
- **JavaScript** orchestrates device functions (app switching, data fetching), not game navigation.
- **Content** (reference entries, skill descriptions, status messages) is written as PB3K documentation — operational, bureaucratic, exceedingly dry. Never as game tutorial text or lore dumps.
- **Errors and empty states** return 204 (no signal / no data) rather than "nothing here" messages.

**PB3K voice** — see `docs/ToneGuideForPB3K.md` for the full editorial test. The
PB3K is an instrument, not a narrator. It observes, measures, records, and
reports; it does not speculate, persuade, comfort, frighten, or entertain. Humor
is rare and dry enough that it may not register on first contact — it comes from
understatement, never punchlines. Two registers exist:

- **Strict sensor register** (crier messages, system messages, reference entries,
  skill descriptions): the PB3K reports only what an instrument could honestly
  know. No culturally loaded language (magic, miracle, treasure); prefer
  recovered object, signal source, anomalous geological structure. Acknowledge
  uncertainty ("Composition unknown." "Confidence: Low.").
- **Developing voice** (artifact `intro` / `signals` / `collapse`): the PB3K is
  developing a voice and is permitted to convey sensory observation to the
  operator about the artifact in hand — "The box is warm to the touch," "The
  metal creaks and pulses." These remain observations, not interpretations
  ("This artifact is dangerous" / "wants something" are still disallowed), and
  they pass the editorial test: *could an instrument with a developing voice
  report this to its operator?*

Operator vitals displayed in the status strip (AP, score, day) are exact
measurements; uncertainty applies to the world and its artifacts, not to the
operator's own state.

The PB3K framing is not a lore decoration — it is a **design constraint** that prevents the UI from becoming a conventional game dashboard. Every feature must be implementable as a PB3K function or it does not belong in the device screen.

The device screen is a fixed-chrome terminal display: status strip (top),
nav bar, two-pane content area (primary + secondary), context bar (bottom).
Visual language: monochrome amber on black (`#c4b998`/`#c49a4a`/`#0a0a0a`),
single monospace font (IBM Plex Mono), bordered panels with uppercase headers,
no progress bars/charts/hover-reveal. 204 renders as empty panel. Every
interaction is a verb-labeled button (PROSPECT, PUSH, STOP, OFFER).

---

## 2. Core Gameplay Loop

```
Login/join season
  → Each day: 20 Action Points (AP, configurable via `default_action_points`, default 20). AP are fully refreshed at day rollover — unused AP are lost.
    → Prospecting (costs `prospect_ap_cost`, default 2 AP)
      → Artifact is drawn from weighted pool
      → Random event may fire (personal, per-character, 20% base chance per begin)
        → Events apply immediate effects: scrap, score, artifact value/instability,
          behavior tags, or AP adjustments. Conditions gate eligibility (score,
          skill level, day, artifact stage). Catch-up events use score_lte to
          help trailing players.
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

    → Cert Training (no AP cost, costs scrap)
      → Buy or upgrade seasonal cert modules

    → Rival Pressure (optional, scrap cost)
      → Press a leaderboard rival's faction lead with one of three effects:
        - Corner the Market: drops trait-saturation multiplier to floor
        - Spoil the Lead: sets rival's next customer irritation to threshold-1
        - Outbid: caps rival's next customer absolute budget at 80%
      → Each pressure carries a self-splashback on the attacker
      → One-shot per (target, faction, effect); stacks up to N (default 3)
      → Expires after N days if unfired (lazy purge on read)

  → Day rollover: refresh AP, artifact decay tick, season day increments
  → Season ends after N days (admin-triggered)
```

### Key structural rules:
- Prospecting and selling are **separate activities** with different AP costs.
  Prospecting costs `prospect_ap_cost` (default 2 AP, overridable by global events
  via `daily_modifiers.prospect_ap_cost`). Market visits cost 1 AP.
- Artifacts enter the Shed after prospecting. Selling happens later, possibly
  on a different day.
- AP are refreshed fully at day rollover. Unused AP are lost.
- Cert training does not cost AP but costs scrap.

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
  ├── Backup data files to date-stamped directory
  ├── Set in_maintenance flag (gates write routes → HTTP 503)
  ├── Advance next_run to next day
  ├── Invoke on_maintenance callback
  │     (see §8.1 for full 15+ step sequence including: bot daily runs,
  │      clearing daily_modifiers, increment season.day, refresh AP,
  │      artifact decay, faction climate, global events, crier,
  │      faction snapshots, transcript logging, check season end)
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

A central Engine coordinator was rejected. Mojolicious is already the
application lifecycle root — it provides event loop, HTTP dispatch, timers,
and lifecycle hooks. Adding an Engine on top creates an artificial second
coordinator. The real architectural rule is: *gameplay behavior must not leak
into controllers, raw state hashes, timers, or persistence plumbing.* That
rule is satisfied by focused service classes (Activity, Shed, Model::Character)
without a central dispatcher. See §3.3 for the maintenance design that
replaced the Engine pattern.

---

## 4. Module Boundary Table

Each module has strict constraints. The "Must NEVER Hold" column is the
critical invariant — the "May Hold" column is implied by module name.

| Module | Must NEVER Hold |
|--------|-----------------|
| **Controller::*** | Game logic, phase validation, artifact math, persistence orchestration |
| **Activity (base)** | Game math, artifact knowledge, YAML content interpretation |
| **Activity::Prospecting** | Market logic, Shed offers, other players' data |
| **Activity::MarketVisit** | Prospecting logic, artifact push math |
| **Activity::BlackMarket** | MarketVisit logic, faction standing, normal bazaar customer state |
| **Shed** (inventory manager) | Market, Faction objects, Account model |
| **Model::Character** | Game math, artifact logic, state mutation outside of CRUD |
| **Model::ShedItem** | Game logic, decay math, faction rules |
| **Model::Account** | Game logic, season data, character data |
| **Model::Season** | Per-player character data, game logic |
| **Model::FactionSnapshot** | Game logic, character data |
| **Model::Session** | Game logic, character data |
| **Nav** (Controller::Nav) | Game logic, character data |
| **Skills** / **CERTS** (YAML loader) | Game logic, character state |
| **Maintenance** | Game math, artifact logic, character internals |
| **ValueTier** (pure function) | App reference, game state, model objects |
| **Artifact** / **Customer** (view models) | Game logic, persistence |
| **Content** (YAML helpers) | Model persistence, game rules, URL construction |
| **SeasonReport** (recap builder) | Model objects, app reference, game logic, formatting, HTML |
| **Service::SkillTraining** | Game rules, view logic, URL construction |
| **Service::Navigation** | Game rules, persistence, template rendering |
| **Service::SeasonManager** | — |
| **Service::Suggestion** | Game rules, persistence operations |
| **Service::RandomEvents** | Character models, Market, Faction objects, transcript references, persistence operations |
| **Service::Authentication** | Direct persistence (mutates Account columns via Account model API), session management, character data, game logic |
| **Service::BotRunner** | Direct model mutation except through Activity dispatch |
| **Service::Dominance** | Character data, market negotiation state, persistence (read-only — writes via season model API) |
| **Service::PvP** | Character state mutation outside of `apply_pressure`, market negotiation logic |
| **Service::MarketGate** | Game rules, controller decisions, phase validation. Returns bool — never mutates. |
| **Model::BrokersCache** | Game logic, market rules, character data |
| **Bot::BlackMarketPolicy** | Activity dispatch, persistence operations |
| **Transcript** (event recorder) | Game rules, account management |
| **Faction** (buyer definition) | Character data, player identity |
| **Bot** (automated player) | Direct persistence (uses same models and activities as controllers) |

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

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| username | string | Unique, used as login credential |
| token_hash | string | bcrypt of 6-char login token |
| remember_token_hash | string or '' | bcrypt of 10-char remember-me cookie |
| recovery_code_hash | string | bcrypt of one-time recovery code |
| banned | boolean | Account locked when true |
| createdAt | timestamp | |
| updatedAt | timestamp | |

Survives across seasons. Contains no gameplay data.

**Authentication model**: Login tokens are 6-char `[A-Z2-9]` (30 bits),
recovery codes are 10-char, remember-me tokens are 10-char in a signed
30-day cookie. All three stored only as bcrypt hashes; plaintext returned
exactly once then discarded. Token reset replaces all three atomically.

### 5.2 Season (tournament)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| label | string | e.g. "Season 1" |
| status | enum | upcoming / active / archived |
| day | integer | Starts at 1 |
| length | integer | Total days |
| end_of_day_hour | integer | 0–23, maintenance fires at this hour |
| faction_state | map | Per-faction: influence, artifacts_received, daily_intake, days_since_purchase, intake_by_trait |
| faction_climate | map or null | Dominant faction climate (draw_biases, budget_delta, banned_traits, etc.) |
| crier_message | string or null | Latest Town Crier text |
| crier_snapshot | map or null | Previous faction_state copy for crier diffing |
| daily_modifiers | map or null | instability_growth_delta, artifact_value_mult, collapse_mult, etc. Cleared each maintenance |
| global_event_text | string or null | Latest global event narrative |
| personal_event_counts | map or null | Per-character catch-up tracking |
| last_maintenance | timestamp | Used by catch-up on restart |

### 5.3 Model::Character (one per player per season)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| account_id | UUID | FK to PlayerAccount |
| season_id | UUID | FK to Season |
| name | string | Snapshot at season start |
| score | integer | Cumulative sale value. NEVER decreases |
| scrap | integer | Spendable currency |
| action_points | integer | Current AP remaining |
| action_points_max | integer | Daily AP cap (default 20) |
| faction_sales | map | Per-faction sale count |
| standing | map | Per-faction reputation |
| pending_activity_id | string or null | FK to activities.json |
| skill_prospecting | integer | 0–max (per YAML) |
| skill_upcycling | integer | 0–max (per YAML) |
| skill_selling | integer | 0–max (per YAML) |
| skill_smuggling | integer | 0–4 |
| black_market_opportunity_offered_today | 0/1 | Reset daily |
| smuggle_reroll_used | 0/1 | SMUGGLING lv4 daily reroll consumed |
| current_location | string | Default: `camp` |
| current_view | string | Last active view, managed by Nav |
| loyalty_visits_since | integer | Non-top-faction visits counter |
| is_bot | integer | 0/1 |
| bot_profile_id | string | Null for humans |
| faction_snubs | map | Per-faction rejected offers |
| snub_day | integer or null | Last snub season day |
| result | hashref or null | Outcome card payload |
| seen_orientation | integer | 0/1 |
| settings_muted | integer | 0/1, reserved for UI |
| onboarding | integer | Tab-reveal bitmask |
| pending_notices | integer | Un-dismissed notice bitmask |

> `turns_remaining` is still present in the column declaration but is
> vestigial — never read or updated during gameplay. It was set by the
> `create_season` command for legacy support. The old "lazy rollover" design
> using `last_refreshed_day` was already removed in favor of in-process
> maintenance AP refresh.

**Invariants enforced by Model::Character:**
- `action_points` cannot go below zero and cannot exceed `action_points_max`
- `scrap` must be non-negative
- `pending_activity_id` must reference a valid activities.json row if set
- `score` never decreases
- Attempting to start a prospecting or market activity without sufficient AP
  is a hard error
- Skills are 0–4, inclusive

**Property distinction:**
- `score` = cumulative seasonal leaderboard value from artifact sales, never decreases
- `scrap` = spendable seasonal currency, may decrease through skill purchases

### 5.4 ShedItem (shed.json)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| char_id | UUID | FK to character |
| artifact_id | string | Original spec ID |
| original_value | integer | At stop time |
| decayed_value | integer | Current after decay |
| condition | enum | fresh / settling / fading |
| days_in_shed | integer | Decay ticks applied |
| instability | integer | At stop time |
| stage | string | stable / strained / unstable |
| push_count | integer | |
| has_evolved | boolean | |
| behaviors | arrayref | Trait tags (copied from spec) |
| archetypes | arrayref | Thematic grouping |
| estimated_value_min | integer | Shown to player |
| estimated_value_max | integer | Shown to player |
| createdAt | timestamp | |
| updatedAt | timestamp | |
| decay_modifiers | map | Snapshot of per-artifact decay params |

The `behaviors` array is the key field for faction interest matching during
market negotiation. Copied from the artifact spec at stop time so that the
shed item is self-contained.

### 5.5 Activity (activities.json)

One row per active game session. FK from `character.pending_activity_id`.
Deleted when phase returns to `idle`.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | |
| char_id | UUID | FK to characters.json |
| type | string | prospecting / market_visit / black_market |
| phase | string | State-machine phase |
| artifact | hashref or null | Live artifact state (prospecting) |
| customer | hashref or null | Customer/deal state (market_visit, black_market) |
| pending_event | hashref or null | Choice event awaiting resolution |
| createdAt | unix timestamp | |
| updatedAt | unix timestamp | |

The `offers` column is removed — selling no longer happens inside a
prospecting activity. Offers are replaced by the negotiation flow in the
MarketVisit activity.

The `customer` column shape includes: `faction_id`, `faction_name`,
`desired_behaviors`, `base_multiplier`, `portrait_id`, `disposition`,
`irritation`, `irritation_threshold`, `settle_chance`, `soft_budget`,
`absolute_budget`, `spent_so_far`, `loyalty_free_mismatches`,
`pending_counter`, `last_message`, `last_sale`, `climate_trait_biases`.
The effective multiplier is computed at offer time by `_dynamic_multiplier()`.

The `artifact` column shape includes: `id`, `value`, `instability`, `stage`,
`push_count`, `max_instability`, `instability_growth_min/max`,
`base_gain_min/max`, `can_evolve`, `has_evolved`, `evolution_threshold`,
`evolution_chance`, `evolution_instability_spike`,
`breakthrough_multiplier_min/max`, `state_thresholds`.

### 5.6 FactionSnapshot (daily faction history)

| Field | Type |
|-------|------|
| id | UUID |
| season_id | UUID |
| day | integer |
| faction_id | string |
| influence | integer |
| artifacts_received | integer |
| intake_by_trait | map |

One row per faction per day, written during maintenance and season end.
Append-only. Last snapshot per faction is authoritative final influence.

---

### 5.7 SeasonFactionState (per-season live faction tracking)

| Field | Type |
|-------|------|
| faction_id | string |
| season_id | UUID |
| influence | integer |
| artifacts_received | integer |
| intake_by_trait | map |
| daily_intake | integer |
| days_since_purchase | integer |

Embedded in `season.faction_state`. Updated on every sale, reset during
maintenance. Used by market dynamics (§6.7).

### 5.8 ArtifactDisposition (per-sale record)

| Field | Type |
|-------|------|
| disposition_id | UUID |
| season_id | UUID |
| player_id | UUID |
| faction_id | string |
| season_day | integer |
| value_awarded | integer |
| artifact_snapshot | JSON |
| standing_delta | integer |
| influence_delta | integer |
| narrative_hooks | JSON |

Append-only, immutable. Created on every successful sale. Survives character
deletion.

### 5.9 SeasonRecord (post-season archive)

| Field | Type |
|-------|------|
| record_id | UUID |
| season_id | UUID |
| player_id | UUID |
| final_score | integer |
| final_scrap | integer |
| rank | integer |
| faction_standing_snapshot | JSON |
| skills_snapshot | JSON |
| story_highlights | JSON |
| created_at | timestamp |

Created during season finalization. Served as `season_recap` on first
`/game` visit after season ends.

### 5.10 Skill/Cert Definition (content/skills.yml)

Cert modules are YAML-defined, not hardcoded. Schema per skill:
`id`, `name` (UI label), `description`, `max_level`, `levels[]` with
`level`, `cost` (scrap), `description`. Internal column names use legacy
IDs (`skill_prospecting`, `skill_upcycling`, `skill_selling`,
`skill_smuggling`). Mechanical effects per level — see §6.6.

### 5.11 Entity Lifecycle

```
PlayerAccount ─── persists forever ──────────────────────►
       │
       ├── Season 1 ─── Model::Character ──► deleted ──►
       │                     │
       │                     ├── ShedItem (created after prospecting stop)
       │                     ├── Skill levels (bought with scrap, columns on character)
       │                     ├── Activity (created/loaded per request, deleted on idle)
       │                     └── ArtifactDispositions (survive)
       │
       ├── Season 2 ─── Model::Character ──► deleted ──►
       │
       └── SeasonRecords (permanent archive)
```

A Model::Character may be deleted ONLY after:
1. Season finalization creates a SeasonRecord
2. All SeasonRecords are verified as stored
3. All owned ShedItems are liquidated at 25% via clearance sale, then forfeit
4. Then hard-deletion is permitted

### 5.12 Pressure (pressures.json)

| Field | Type |
|-------|------|
| id | UUID |
| attacker_id | UUID |
| target_id | UUID |
| faction_id | string |
| effect_type | enum | corner_market / spoil_lead / outbid |
| target_consumed | 0/1 |
| attacker_consumed | 0/1 |
| createdAt | timestamp |
| updatedAt | timestamp |

Row deleted lazily when both consumed flags are 1, or purged after
`pvp_pressure_max_age_days` (default 7). See §6.8 for effect lifecycle.

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
   - Global events may set `daily_modifiers.instability_growth_delta` which is
     added to growth. The per-character upcycling skill's
     `instability_growth_reduction` from `content/skills.yml` is subtracted
     (growth floors at 1).

3. **Stage determination**: `ratio = instability / max_instability`
   - `ratio <= stable_threshold` → "stable"
   - `ratio <= strained_threshold` → "strained"
   - `ratio > strained_threshold` → "unstable"
   - Default thresholds: `stable: 0.30`, `strained: 0.65` (set in `state_thresholds` per artifact spec)

  4. **Collapse check**: Zero below `stable` threshold; above it the curve is shifted
     so collapse starts at 0 at the threshold boundary:
     ```
     if ratio > stable_threshold:
         stressed = (ratio - stable_threshold) / (1 - stable_threshold)
         collapse_chance = (stressed³) × 0.80 × collapse_mult
     ```
     - `collapse_mult` comes from `daily_modifiers.collapse_mult` (set by global events).
       Default is 1.0. This allows global events to increase or decrease collapse severity.
     - Clamped to maximum 100%
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
   - `gain` is further increased by the upcycling `value_gain_bonus` from
     `content/skills.yml` (not `upcycling_level - 1` — the bonus is defined
     per-level in the YAML effects block)
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

**Player-facing value**: The player never sees the exact `decayed_value`.
What is shown is either a fuzzy tier label (via `ValueTier::describe`) or the
estimated range (`estimated_value_min`–`estimated_value_max`). The raw
`decayed_value` and `original_value` are server-only — they are computed and
stored but never rendered to the player.

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

1. **Customer generation** (read-only — does not modify state): A customer
   struct is generated from the eligible faction pool, with:
   - `faction_id`, `faction_name`
   - `desired_behaviors` — a subset of the faction's interests (hidden from player)
   - `base_multiplier` — the faction's standard offer multiplier
   - `irritation` — starts at random 0–3 (varies per visit, press-your-luck from the outset)
    - `irritation_threshold` — if exceeded, customer leaves (default 4)
   - `settle_chance` — probability the customer will accept a non-matching item
    - `soft_budget` — 30–59 base + 5 per standing point with this faction
   - `absolute_budget` — 1.2 × soft_budget (hard cap)
   - `spent_so_far` — cumulative value of all purchases this visit (starts 0)

   Customer selection is standing-weighted: each faction's weight starts at 1.0
   and increases by +0.25 per point of personal standing with that faction
   (standing capped at 10 for weight calculation). Each prior snub (send_away
   or storm-off) subtracts 0.25 from weight, floored at 0.2. The higher a
   player's standing with a faction, the more likely its customers appear.

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
    - Delete ShedItem (via `$self->app->shed->delete`)
    - With multi-item disabled: activity row deleted, `pending_activity_id` cleared
    - With multi-item enabled: activity persists, `pending_activity_id` stays set

   All sale persistence goes through public Character/Shed APIs (`setCol`, `save`,
   `delete`) — never internal model state. The generated customer struct itself is
   never persisted as a standalone entity; it lives only in the activity row.

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

### 6.6 Skills / CERTS (Mechanical Effects)

Cert modules are purchasable per season via the Skills controller (`POST /skills/purchase`).
Cert modules have YAML-defined max levels. Current maxes are GEO-SENSE 3, DEFRAG 4, and UP-CEL 3. Effects are applied
at the point of use (draw, push, stop, offer) by reading the character's
skill columns. The internal column names use the legacy IDs (`skill_prospecting`,
`skill_upcycling`, `skill_selling`); the UI labels are the cert module names.

**GEO-SENSE (prospecting, levels 1–4)** — affects artifact drawing and base value:

| Level | Effect |
|-------|--------|
| 1 | Trait tags visible in salvage ledger; `-` placeholder when untrained |
| 2 | `base_value` of drawn artifact increased by +2 |
| 3 | `base_value` increased by +4 total; weight doubled for artifacts with `base_value >= 8` (higher chance of rich finds) |
| 4 | `base_gain_min` and `base_gain_max` each increased by +1 per push |

**DEFRAG (upcycling, levels 1–4)** — reduces instability growth during pushes:

| Level | Effect |
|-------|--------|
| 1 | Instability growth reduced by 1 per push (min 1) |
| 2 | Growth reduced by 2; value gain per push increased by +1 |
| 3 | Growth reduced by 3; value gain increased by +2; `evolution_chance` increased by +0.02 |
| 4 | Phase cancellation array — reduces initial artifact instability according to the YAML effects block |

Instability growth floors at 1 — even max upcycling cannot fully
eliminate instability.

**UP-CEL (selling, levels 1–3)** — improves market outcomes:

| Level | Effect |
|-------|--------|
| 1 | Estimate range narrowed from ±20% to ±15% at stop time |
| 2 | Irritation gain on mismatches eliminated (gain = 0 instead of 1) |
| 3 | Customer budget range revealed; match multiplier increased from 1.2× to 1.4× `base_multiplier` |

**SHADOW-ROUTE (smuggling, levels 1–4)** — reduces Black Market seizure risk:

| Level | Effect |
|-------|--------|
| 1 | Seizure risk reduced by 5 percentage points |
| 2 | Seizure risk reduced by 10 percentage points |
| 3 | Seizure risk reduced by 15 percentage points |
| 4 | Seizure risk reduced by 20 percentage points; first seizure each day gets one free reroll |

Skill costs are defined entirely in `content/skills.yml`. Skill training
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

### 6.9 Black Market (Press-Your-Luck Selling)

When a faction is dominant (climate intensity >= `leading`, margin > 4), its
climate profile's `banned_traits` list (1-2 artifact behavior tags) becomes
active. Items with banned traits cannot be offered to the dominant faction
during normal Bazaar negotiation (the customer refuses them).

On the player's first Bazaar visit of the day while bans are active and the
player has at least one banned item in the shed, the broker intercepts instead
of a normal faction customer. The Black Market is **not a separate nav item** —
it appears inside the Bazaar panel as a modal offer.

**Broker offer formula**:
```
premium_mult = 1.2 + (decayed_value / 100) * 0.4    // capped at 2.5x
seizure_chance = 0.05 + (decayed_value / 200) * 0.30 // capped at 0.35
offer_value = floor(decayed_value * premium_mult)
```

Both premium multiplier and seizure chance are **shown to the player**. Higher
value items offer larger premiums but carry higher risk — this is the
press-your-luck tension.

**SMUGGLING skill** (`skill_smuggling`, 0–4): Each level reduces seizure chance
by 5 percentage points (level 4: -20%). Level 4 also grants one daily reroll:
if the first seizure roll fails, the player can reroll once.

**Outcome**:
- **Sale**: Player receives `offer_value` as scrap+score. Shed item deleted.
  No faction standing change. Recorded as disposition with faction_id
  `black_market`.
- **Seizure**: Total loss. Shed item deleted. Nothing awarded. Artifact logged
  to `Model::BrokersCache` for future recovery (random event).
- **Withdraw**: Player walks away. Item stays in shed. AP consumed.

**BrokersCache**: Seized artifacts are logged to `data/brokers_cache.json` with
an `available` flag. A future random event type (`brokers_cache_resurface`) can
draw from this pool and restore an artifact to a player's shed.

**One visit per day**: The `black_market_opportunity_offered_today` flag on the
character prevents multiple broker encounters in a single day. Reset during
daily maintenance.

#### Implemented

- **Black Market**: `Activity::BlackMarket`, `Controller::BlackMarket`,
  `Service::MarketGate`, `Model::BrokersCache`, `Bot::BlackMarketPolicy`
- **SMUGGLING skill**: YAML-driven, reduces seizure chance, level 4 reroll

#### Planned (not yet implemented)

- **Desperate Recruiter**: When a faction trails significantly in influence,: `content/events/prospecting.yml` (fires during `Prospecting::begin`, 20% base chance), `content/events/market_visit.yml` (fires during `MarketVisit::begin`, 15% base chance), `content/events/global.yml` (fires during daily maintenance on `day_start` trigger, 60% base chance). All three are implemented. Events use YAML-driven condition/effect dispatch tables with `Service::RandomEvents`. Prospecting events include catch-up rubberbanding via `score_lte`.

#### Planned (not yet implemented)

- **Desperate Recruiter**: When a faction trails significantly in influence,
  faction-specific events offer premium standing gains or bonus scrap. Gated
  behind `faction_sales[faction_id] >= 1`.

### 6.8 Rival Pressure (PvP)

Players and bots can spend scrap to apply a one-shot debuff ("pressure") to a
leaderboard rival's next market interaction with a faction. Pressures are
asynchronous, targeted, and carry a self-splashback: every effect that hits
the rival also hits the attacker on their next visit/sale to the same faction.

**Eligibility**: The attacker must have an active season character, the target
must be ranked strictly above the attacker on the leaderboard, and the target
must have sold at least one artifact to the pressed faction
(`faction_sales[F] >= 1`). Config master switch: `pvp_enabled`.

| Option | Effect on rival (next sale/visit to F) | Self-splashback | Configurable cost |
|---|---|---|---|
| **Corner the Market** | Forces that faction's effective trait-saturation to the floor for one trait — drops multiplier to `market_max_saturation_discount` on that sale | Attacker's next sale to F also floors saturation | `pvp_cost_corner_market` (50) |
| **Spoil the Lead** | Rival's next customer from F starts with `irritation = irritation_threshold - 1` — one mismatch away from storm-off | Attacker's `standing[F]` -= `pvp_splash_standing_loss` (1), fires immediately on application | `pvp_cost_spoil_lead` (30) |
| **Outbid** | Rival's next customer from F has `absolute_budget` capped at `pvp_splash_budget_ratio` (0.80) | Attacker's next market visit with a customer from F also budget-capped | `pvp_cost_outbid` (75) |

**Firing**: Target effects are consumed on the target's next qualifying
market interaction with F (MarketVisit `begin` for visit-level effects;
`offer`/`stand_pat`/`_do_sale` for sale-level effects). Attacker splashbacks
fire identically on the attacker's own next interaction with F. Only one
pressure fires per visit/sale (FIFO order). Row is deleted when both
`target_consumed` and `attacker_consumed` are 1.

**Stacking**: Up to `pvp_max_stack` (default 3) pending pressures per
(target, faction) pair.

**Expiry**: Unfired pressures are lazily purged after
`pvp_pressure_max_age_days` (default 7) on the next read — no maintenance
hook is used, preserving §17 #10.

**Scrap cost**: All costs configurable via `magic_mountain.yml` under the
`pvp_*` keys. No AP cost — pressure competes with skill purchases for scrap,
not with prospecting/market AP budget.

**Visibility**: Named immediately. The target's Crier context bar shows
"<attacker> is pressing your <faction> lead — <effect_type>." on the next
`GET /nav` after a pressure is applied.

**Bot participation**: Bots press rivals via `Bot::PressurePolicy` during
their daily `BotRunner::run_day` cycle (after prospecting and market visits,
so scrap is final). Target selection is faction-aware: bots only press
rivals on factions the bot itself sells to, which naturally distributes
pressure by interest and prevents leader dog-piling. Each bot has a
per-profile `pvp_aggressiveness` field in `content/bots.yml` (default
global: `pvp_bot_aggressiveness`, 0.20).

**Architecture constraint**: All three effects reuse §6.7 vocabulary
(saturation, irritation, budget) — no new multiplier terms are added to
`_dynamic_multiplier`. The saturation floor is a one-way clamp downward
(pressure can only worsen a sale, never improve it). This preserves §17 #13.

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

### 7.3 Faction Voice

Faction identity stays visible to the player (`faction_name` is always returned
by `Market#begin`). Recognition is *not* gated through hidden identity. Instead,
the manner in which a customer presents to the player must sharply express the
faction's worldview — the player should come to anticipate, before reading the
name, which faction has arrived based on voice alone.

**Authority**: `docs/ToneGuideForFactions.md` (per-faction vocabulary, emotional
temperature, market behavior) and `docs/MechanicsRevealFactions.md` (recognition
over explanation; mechanics first, lore second).

**Editorial test for faction dialogue**: before approving a line, ask —
1. Does this line reveal the faction's worldview (what it believes the Mountain is for)?
2. Could another faction plausibly have said it?

If the answer to #2 is yes, rewrite the line until only one faction could have
spoken those words. No faction is a cartoon villain or paladin; each sincerely
believes its own worldview and is never written as lying to the player about it.

**Presentation contract**: the static `disposition` label ("commercial_resale",
"sacred_custody", "destruction") is exposition — it tells rather than shows.
It is currently returned to the client but not directly displayed to the
player. It will eventually be superseded by an in-character **arrival line**
drawn from faction-voiced content (`content/flavor/negotiation_reactions.yml`
`arrival:` category, **not yet implemented**). The `disposition` label is a
server-only classification for styling and commodity hooks; it should not
be displayed to the player.

### 7.4 Commission System — Planned

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

### 7.5 Faction Climate / Dominance

Each day during maintenance, `Service::Dominance::calculate_climate` computes
which faction has the highest influence (`faction_state.influence`). If the
influence margin between leader and runner-up exceeds a threshold (contested ≤4,
leading ≤12, strong ≤24, dominant >24), the leader's climate profile applies.
Climate profiles are defined per-faction in `content/factions.yml` under a
`climate` key. In addition to numeric deltas, each profile may declare
`banned_traits`: a list of artifact behavior tags that the dominant faction
refuses to handle. When a faction is dominant (margin > 4), items with banned
traits cannot be sold to that faction through the normal Bazaar — the customer
refuses them. This opens the Black Market channel (see §6.9).

```yaml
climate:
  budget_delta: 10           # Adds to soft_budget in MarketVisit
  patience_delta: 1          # Adds to irritation_threshold (dominant faction only)
  draw_biases:               # Prospecting: boosts certain behavior weights
    thermal: 1.5
  starting_instability_mod: -1  # Reduces starting instability
  buyer_trait_biases:        # Market: premium for certain traits
    force: 0.10
  banned_traits: [force, instability]  # Traits the dominant faction refuses to handle
```

All deltas are scaled by intensity factor (1× for leading, 1.5× for strong,
2× for dominant). The resulting climate object is stored in
`season.faction_climate` and affects:

| Mechanic | Effect | Source |
|----------|--------|--------|
| Prospecting draw biases | Multiplies artifact behavior weights during draw | `climate.draw_biases` |
| Starting instability | Modifies base instability of drawn artifacts | `climate.starting_instability_mod` |
| Buyer budgets | Adds/subtracts from soft_budget | `climate.budget_delta` |
| Buyer patience | Adds to irritation_threshold (dominant only) | `climate.patience_delta` |
| Buyer trait biases | Adds multiplier to match offers for specific traits | `climate.buyer_trait_biases` |
| Banned traits | Traits the dominant faction refuses to buy (→ Black Market channel) | `climate.banned_traits` |
| Crier text | Generates per-faction headline/hint for Town Crier | `climate → crier_text` |

The climate object also generates `crier_text` for the Town Crier, providing
in-character narrative about market conditions. Climate is recalculated daily
and stored on the season model (not appended — replaced each cycle).

### 7.6 Global Events & Daily Modifiers

Global events are drawn from `content/events/global.yml` with trigger
`day_start` during maintenance (60% base chance). Unlike personal events,
they affect the entire season for one day by setting `daily_modifiers` keys
on the season:

| Modifier Key | Effect | Default |
|-------------|--------|---------|
| `instability_growth_delta` | Added to instability growth per push | 0 |
| `artifact_value_mult` | Multiplier on base_value during artifact draw | 1.0 |
| `market_multiplier_delta` | Added to market dynamic_multiplier | 0 |
| `prospect_ap_cost` | AP cost for `Prospecting::begin` | 2 |
| `collapse_mult` | Multiplier applied to collapse chance formula | 1.0 |

Modifiers are cleared at the start of each maintenance cycle (before the new
day's event is drawn), so they last exactly one day. Condition gating uses
the same `conditions` system as personal events (see `Service::RandomEvents`),
with a `global`-pool condition registry that includes `any_faction_days_no_buy_gte`.

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
receives the Maintenance object (`$self`). Implementation (executed in this
exact order):

1. **Bot daily runs** (only when NOT catching up): If bots are configured
   (`bots.count > 0`), seed RNG with season_id + day, shuffle bot characters,
   and run each bot's daily cycle via `BotRunner::run_day`. Bot events are
   written to a separate transcript file (`transcript_bots.jsonl`) to keep
   the main game transcript clean.

2. **Clear yesterday's modifiers**: `daily_modifiers` and `global_event_text`
   are cleared to make way for the new day's global events.

3. **Increment `season.day`** by 1

4. **For every Model::Character**: reset `action_points` to
   `action_points_max` (default 20, configurable)

5. **Apply artifact decay** to every ShedItem (see 6.4)

6. **Reset market dynamics state**: For each faction in `faction_state`:
   `daily_intake = 0` and `days_since_purchase++`.

7. **Faction climate calculation**: `Service::Dominance::calculate_climate`
   computes the dominant faction based on influence ranking, scales their
   climate profile by intensity tier (contested/leading/strong/dominant),
   and writes `faction_climate` to the season. Climate affects prospecting
   draw biases, buyer budgets/patience, and crier text.

8. **Global event draw**: `Service::RandomEvents::draw` selects from
   `content/events/global.yml` with trigger `day_start`. If an event fires,
   its effects are applied to the season (setting `daily_modifiers` keys
   like `instability_growth_delta`, `artifact_value_mult`, etc.) and
   `global_event_text` is stored for Crier priority.

9. **Generate Town Crier message**: Crier reads `global_event_text` first
   (highest priority). If none, it diffs current `faction_state` against
   `crier_snapshot`, selects the highest-priority message template (faction
   dominance, surge, milestone, slump, daily progress, or generic), and
   stores the result in `crier_message`.

10. **Update `crier_snapshot`** to current `faction_state`.

11. **Write FactionSnapshot rows**: For each faction in `faction_state`,
    create a snapshot row with season_id, day, faction_id, influence,
    artifacts_received, intake_by_trait.

12. **Log transcript event** with full faction_state and crier message.

13. **Record `season.last_maintenance`** as a Unix epoch timestamp.

14. **Preserve activity rows** — in-progress prospecting/market visits
    survive rollover naturally (no explicit cleanup).

15. **If `season.day > season_length`**, emit a warning (season end is
    manual — the game does not auto-finalize).

**Catch-up on server restart** (`_catch_up_maintenance`):

When the application starts, it checks whether the active season's
`last_maintenance` timestamp precedes the most recent end-of-day boundary.
If so, it runs the `on_maintenance` callback once per missed cycle,
advancing the season by the corresponding number of days.

```
last_maintenance < recent_boundary  →  missed = floor((boundary - last) / 86400) + 1
                                      catch_up(missed)
```

During catch-up, the `on_maintenance` callback receives a `time_warp` signal.
The Crier picks from a `time_warp` message template instead of the usual
faction-diff logic, producing messages like "TIME WARP DETECTED".

This handles both multi-day outages (server down for a week) and short
overruns (server restarted minutes after midnight — the boundary check
captures the window that was just missed).

The `catch_up` method on `Maintenance.pm` sets the `in_maintenance` flag
for the duration and clears it after all cycles complete.

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
3. For each Model::Character:
   a. Collect final stats (score includes clearance, scrap includes clearance,
      standing, faction_sales, skills)
   b. Collect significant ArtifactDisposition records
   c. Build SeasonRecord (score, scrap, rank, standing snapshot, skills
      snapshot, disposition summaries, narrative hooks, clearance_bonus)
   d. Store SeasonRecord (append-only, survives deletion)
4. Verify ALL SeasonRecords are stored successfully
5. Discard all ShedItems for this season (already liquidated in step 2)
6. Delete ALL Model::Character rows for this season
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

**Dispatch**: Reads `$self->phase` (column accessor), validates against
`transitions` table, checks handler exists via `$self->can($action)`,
delegates to `$self->$action($char, %params)`. Handlers set phase directly
(`$self->phase('processing')`) — no `next_phase` or serialize ceremony.

**Content loading**: `load_content` calls `LoadFile($self->content_filename)`
once, stores in `content_data`. Propagated to per-request instances via
overridden `get()`/`create()`.

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

`instability`, `evolution_chance`, and other internal math must never appear in `view`.

### 9.3 Persistence Topology

`characters.json` rows have a `pending_activity_id` FK to `activities.json`.
`activities.json` rows have `char_id`, `type`, `phase`, `artifact`, `customer`.
`shed.json` rows have `char_id` and artifact state. Skills are YAML content,
not persistence.

### 9.4 Global Instance as Factory

One global instance per activity type (e.g. `$app->prospecting`), constructed
at startup, holding:
- `file` — path to `activities.json` (the persistence table)
- `content_data` — parsed YAML specs, loaded once via `load_content`
- `transitions`, `app`, `log` — shared ephemeral state

Per-request activity rows are created or loaded via the standard Model API
(`$app->prospecting->create(...)` or `$app->prospecting->get($id)`). Both
return fully-functional instances with persisted columns and propagated
ephemeral attributes.

### 9.5 Prospecting Activity

Transitions: `idle → begin → processing → {push, stop, resolve_event}`.
`create` sets `type='prospecting'`, `phase='idle'`. Constructed at startup
with `file`, `app`, `content_filename`, `log`.

**Prospecting flow**: `idle → begin` (deduct AP, draw artifact or fire event,
set phase `processing`). `processing → push` (destabilize; collapse/breakthrough
delete row, normal saves row). `processing → stop` (create ShedItem, delete
row). `processing → resolve_event` (apply choice event, delete row).
Activities own all persistence — controller never calls `save` or `delete`.

### 9.6 MarketVisit Activity

Transitions: `idle → begin → negotiating → {offer, send_away, accept_counter, stand_pat}`.
`create` sets `type='market_visit'`, `phase='idle'`. Constructed at startup
with `file`, `app`, `content_filename`, `log`.

**MarketVisit flow**: `idle → begin` (deduct 1 AP, generate customer, set
phase `negotiating`). `negotiating → offer` (match behaviors → auto-sale;
mismatch → settle roll or irritation++ or counter-offer). `negotiating →
accept_counter` (sale at counter price). `negotiating → stand_pat` (demand
original price; skill+standing roll for acceptance). `negotiating →
send_away` (end, no sale). Terminal outcomes delete the activity row;
non-terminal outcomes save it.

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

Every controller action follows the same pattern: resolve player identity,
load character model, load or create activity row, call
`$activity->dispatch($char, $action, %params)`, render `$result->{view}`.
The controller never calls `save` or `delete` on any model — the activity
handler owns all persistence.

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
| Prospecting | begin, push, stop, resolve_event, show | Prospecting lifecycle + choice event resolution + `GET /prospecting` fragment/JSON. |
| PvP | show, apply | `GET /pvp` — rival list, active pressures, action buttons. `POST /pvp/apply` — spend scrap to apply a pressure. |
| Market | begin, offer, send_away, accept_counter, stand_pat, show | Market negotiation lifecycle + `GET /market` fragment/JSON. |
| Shed | index | List shed contents with condition and estimates. |
| Skills | index, purchase | View available skills, purchase upgrade. |
| Factions | show | `GET /factions` — faction registry with standing and influence. Returns 204 when no active season. |
| Reference | show | `GET /reference/:id` — in-universe registry entry for factions, artifact types, or PB3K terminology. Reads from `content/references.yml`. Returns 204 on unknown id. |
| Home | show | `GET /home` — home dashboard with station status, shed ledger, and contextual suggestions. |
| Leaderboard | index, factions | Player rankings; faction influence time series. |
| Account | show | `GET /account` — account settings panel (logout, delete account). Returns 204 when not logged in. |
| Admin | reset_token, ban, unban | `POST /admin/account/*` — operator endpoints. Gated by `admin_secret` HTTP header (configurable). Reset token: drops and replaces all three auth hashes, returns new token + recovery code. Ban/unban: toggles `banned` and writes audit event. |
| Orientation | show, dismiss | `GET /orientation` — onboarding panel fragment for first-session players (gated by `seen_orientation`). `POST /orientation/dismiss` — sets `seen_orientation = 1` and saves. |
| OnboardingNotice | show, dismiss | `GET /onboarding/notice` — progressive-reveal notice card for a newly-unlocked tab (gated by `pending_notices`). `POST /onboarding/dismiss-notice` — clears the notice bit, tabs remain visible. |
| Season | recap | `GET /season/recap` — returns the last archived season's SeasonRecord for the current player (or 204 when none). Reads from `season_records.json`, not the live season. |

The old `Artifact` controller is renamed to `Prospecting`. The old `Sale`
controller is removed (replaced by `Market`). New `Shed`, `Skills`,
`Admin`, `Orientation`, `OnboardingNotice`, and `Season` controllers are
added for inventory management, skill purchases, operator actions,
progressive onboarding, and recap views.

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

`POST /sessions` accepts `{displayName, token}`. New accounts (validated
`^[a-zA-Z0-9_-]{1,24}$`) are created via `Service::Authentication::new_account`
with bcrypt-hashed token/remember/recovery hashes; plaintext returned once via
`mm_new_credentials` session slot. Existing accounts without a token return
`{need_token: 1}`; with a token, `verify_login` checks bcrypt and rotates the
remember-token. Recovery (`POST /sessions/recover`) accepts `{displayName,
recoveryCode}`, verifies via `verify_recovery_code`, rotates all three hashes.

A signed `mm_remember` cookie (30-day expiry) allows resume without re-entering
the token. Server-side session records track `last_active` with configurable
timeout (default 60 min). `current_player` helper validates on each request.
`DELETE /sessions` / `GET /logout` destroy the session. `GET /player` returns
current player info or 401. `GET /` and `GET /login` redirect to `/game`.

Display names must be unique. Operator actions (`POST /admin/account/*`) gated
by `admin_secret` header. All events recorded in `audit.jsonl`.

---

## 12. Content System (YAML-Driven)

### 12.1 Directory Structure

```
  content/
    bots.yml                        # Bot profile definitions
    prospecting.yml                 # All artifact definitions
    references.yml                  # Reference registry entries (factions, artifact types, terms)
    skills.yml                      # Skill definitions and costs
    factions.yml                    # Faction definitions
    events/                         # Random event pools (YAML-driven)
        prospecting.yml             # Passive + choice events (Prospecting::begin, 20% base)
        market_visit.yml            # Passive events (MarketVisit::begin, 15% base)
        global.yml                  # Global day events (maintenance, 60% base)
    flavor/
        advisories.yml              # System advisory messages (idle, season end, faction hunger)
        crier.yml                   # Daily maintenance messages (surge, slump, etc.)
        negotiation_reactions.yml   # Per-faction flavor text for market visit outcomes
        commission_triggers.yml     # Commission issuance text (unused until §7.3)
        pressure_reactions.yml      # PvP pressure outcome flavor text
        system_messages.yml         # Unit status flavor text (device frame boot message)
```

### 12.2 Artifact Definition Shape

Each artifact spec in `content/prospecting.yml` has these fields:

| Field | Type | Notes |
|-------|------|-------|
| id | string | Unique identifier |
| archetypes | array | Thematic grouping (unused mechanically) |
| behaviors | array | Trait tags for faction interest matching |
| weight | integer | Draw probability weight |
| base_value | integer | Starting sale value |
| starting_instability | integer | Always 0 |
| max_instability | integer | Upper bound for ratio |
| instability_growth_min/max | integer | Range per push |
| base_gain_min/max | integer | Value gain range per push |
| can_evolve | boolean | |
| evolution_threshold | float | Min ratio for evolution check |
| evolution_chance | float | Breakthrough probability per push |
| evolution_instability_spike | integer | Extra instability on breakthrough |
| breakthrough_multiplier_min/max | float | Value multiplier on breakthrough |
| state_thresholds | map | `stable`, `strained` ratio boundaries |
| decay_modifiers | map | `fresh/settling/fading_multiplier`, `settling/fading_day` |
| intro | string | Text on first draw |
| signals | map | Per-stage flavor text arrays |
| collapse | array | Collapse description texts |

If `decay_modifiers` is omitted, global defaults apply.

### 12.3 Skill Definition Shape

Each skill in `content/skills.yml` has: `id`, `name`, `description`,
`max_level`, `levels[]` with `level`, `cost` (scrap), `description`.
See §5.10 for the schema. See `content/skills.yml` for actual values.

### 12.4 Text Content Shape

**crier.yml**: Contains all Crier message categories under `crier_messages`:
`faction_surge`, `faction_slump`, `faction_dominance`, `milestone`,
`season_opening` (day 1), `daily_progress` (ranged by day percentage),
and generic fallback messages. Loaded at startup by `Crier.pm`.
*Tone:* PB3K strict sensor register (§1.1). The Crier is a PB3K channel — it
reports ideological and statistical shifts as observations, never as advocacy.

**commission_triggers.yml**: Per-faction narrative text for commission
issuance. Content-only — loaded by the Commission System when implemented.
*Tone:* faction voice (§7.3).

**negotiation_reactions.yml**: Per-faction flavor text for market visit
outcomes (match, settle, mismatch, storm_off, counter, `mood_*`).
*Tone:* faction voice (§7.3). Loaded lazily by `MarketVisit::_reactions` on
first offer. Falls back to generic text if no faction entry exists. A planned
`arrival:` category will provide the in-character greeting surfaced by
`Market#begin` (§13.3, §7.3).

**prospecting.yml `intro` / `signals` / `collapse`** (§12.2): artifact flavor
text. *Tone:* PB3K developing voice (§1.1) — sensory observation permitted,
interpretation disallowed.

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
| GET | `/health` | (inline) | JSON | Readiness probe — `{"ok":1}`. No auth, no DB reads. Available during maintenance. |
| GET | `/` | `Root#index` | — | Gateway redirect (→ `/game`) |
| GET | `/login` | `Sessions#login_form` | — | Redirects to `/game` (login form is inline in game page) |
| POST | `/sessions` | `Sessions#create` | JSON | Login or auto-create player. Accepts `{displayName, token}`. New accounts return a one-time `{token, recovery_code}` via `mm_new_credentials` session slot. |
| POST | `/sessions/recover` | `Sessions#recover` | JSON | Token reset by recovery code. Accepts `{displayName, recoveryCode}`, replaces all three auth hashes, returns a new `{token, recovery_code}`. |
| GET | `/sessions/token-prompt` | `Sessions#token_prompt` | fragment | Token-entry card (POST `/sessions` body needs `token`). |
| GET | `/sessions/recovery-form` | `Sessions#recovery_form` | fragment | Recovery-code entry card for `POST /sessions/recover`. |
| GET | `/sessions/credentials` | `Sessions#credentials` | fragment | One-time display of freshly generated `{token, recovery_code}`. Consumes `mm_new_credentials` session slot. |
| DELETE | `/sessions` | `Sessions#destroy` | JSON | Logout (API) |
| GET | `/logout` | `Sessions#logout` | — | Logout (browser, redirects to `/game`) |
| POST | `/admin/account/reset-token` | `Admin#reset_token` | JSON | Operator: replace account's auth hashes, return new token + recovery code. Gated by `admin_secret` header. |
| POST | `/admin/account/ban` | `Admin#ban` | JSON | Operator: set `banned = 1`, audit-logged. |
| POST | `/admin/account/unban` | `Admin#unban` | JSON | Operator: clear `banned`, audit-logged. |
| GET | `/orientation` | `Orientation#show` | fragment | Onboarding panel (gated by `seen_orientation`). |
| POST | `/orientation/dismiss` | `Orientation#dismiss` | JSON | Mark onboarding seen, persist. |
| GET | `/onboarding/notice` | `OnboardingNotice#show` | fragment | Progressive-reveal notice card for a newly-unlocked tab (gated by `pending_notices`). Accepts `?notice=<id>` param. |
| POST | `/onboarding/dismiss-notice` | `OnboardingNotice#dismiss` | JSON | Clear the `pending_notices` bit for a specific notice. Accepts `{notice_id}`. |
| GET | `/season/recap` | `Season#recap` | fragment | Last archived season's recap for the current player (or 204). |
| GET | `/game` | `Game#show` | JSON + HTML | Game state page. Renders login form inline when unauthenticated. Response includes `onboarding_notices` (array of newly-revealed tab IDs, empty on subsequent loads). |
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
| GET | `/reference/:id` | `Reference#show` | JSON + fragment | In-universe registry entry by ID. 204 on unknown id. |
| GET | `/account` | `Account#show` | JSON + fragment | Account settings (logout, delete account). 204 when not logged in. |
| GET | `/home` | `Home#show` | JSON + fragment | Home dashboard with station status, shed ledger, and suggestions |
| GET | `/result` | `Result#show` | JSON + fragment | Result display (outcome card for collapse, breakthrough, sale, etc.) |
| GET | `/leaderboard` | `Leaderboard#index` | JSON + fragment | Player rankings |
| GET | `/leaderboard/factions` | `Leaderboard#factions` | JSON | Faction influence time series |
| POST | `/result/dismiss` | `Result#dismiss` | JSON | Clear result and return to home view |
| POST | `/result/continue` | `Result#do_continue` | JSON | Acknowledge result and proceed to next view (used post-breakthrough/orientation). Persists the rule that the result has been shown. |
| POST | `/nav/toggle` | `Nav#toggle` | JSON | Server-side nav state transition (validates tab active and persists `current_view` to character). |
| POST | `/prospecting/begin` | `Prospecting#begin` | JSON | Start prospecting (costs 2 AP) |
| POST | `/prospecting/push` | `Prospecting#push` | JSON | Destabilize artifact |
| POST | `/prospecting/stop` | `Prospecting#stop` | JSON | Halt, create shed entry |
| POST | `/prospecting/resolve_event` | `Prospecting#resolve_event` | JSON | Resolve choice event, body: `{choice_id}` |
| POST | `/market/begin` | `Market#begin` | JSON | Start market visit (costs 1 AP) |
| POST | `/market/offer` | `Market#offer` | JSON | Offer shed item to customer |
| POST | `/market/send_away` | `Market#send_away` | JSON | End negotiation, no sale |
| POST | `/market/accept_counter` | `Market#accept_counter` | JSON | Accept customer's counter-offer |
| POST | `/market/stand_pat` | `Market#stand_pat` | JSON | Hold firm at original price; customer may accept (skill+standing roll) or refuse (irritation++) |
| POST | `/skills/purchase` | `Skills#purchase` | JSON | Buy skill upgrade (costs scrap) |
| GET | `/pvp` | `Pvp#show` | JSON + fragment | PvP panel: rivals ranked above player, active pressures, scrap, action buttons |
| GET | `/black_market` | `BlackMarket#show` | JSON + fragment | Black Market broker panel. 204 when no active black market session. |
| POST | `/black_market/accept` | `BlackMarket#accept` | JSON | Accept broker's offer. Roll for seizure or sale. |
| POST | `/black_market/withdraw` | `BlackMarket#withdraw` | JSON | Decline broker's offer. Item stays in shed. AP consumed. |
| POST | `/pvp/apply` | `Pvp#apply` | JSON | Apply Rival Pressure body: `{target_id, faction_id, effect_type}`. Returns `{ok, pressure{id, effect_type, faction_id, target_id, cost}}` on success |

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

See the endpoint table (§13.1) for route→action mapping and the activity flow
tables (§9.5, §9.6) for phase transitions and persistence. Controllers are thin
dispatch+render pipes — they validate preconditions (AP, activity state), load
or create the activity row, call `$activity->dispatch($char, $action, %params)`,
and render `$result->{view}`.

### 13.4 Response Shape for Game State

Top-level keys: `ok`, `player` (name, AP, scrap, score, faction_sales, skills),
`prospecting` (present when active activity is prospecting), `market_visit`
(present when active activity is market_visit), `shed` (present when idle),
`season` (day, total_days, label), `world_message`, `csrf_token`,
`season_opening`. Both `prospecting` and `market_visit` are null when idle.

---

## 14. Bot Simulation

Bots are automated players that invoke the same service classes as the web
controllers. The simulate CLI command reads artifact content, iterates through
a population of bots, and calls `Activity::Prospecting`, `Activity::MarketVisit`,
`Shed`, and `Model::Character` mutators directly — producing game outcomes
identical to human play. Additionally, during daily maintenance,
`Service::BotRunner` runs each bot's daily cycle (prospect, visit market, apply
PvP pressure) using the same activity dispatch path as human players. The
simulation framework lives across four layers:

- **`MagicMountain::Bot::PushPolicy`** — stateless evaluation of push/stop
  decisions given character state, artifact state, and policy parameters.
- **`MagicMountain::Bot::SellPolicy`** — stateless evaluation of three
  selling decisions: accept customer, offer item, try another after mismatch.
- **`MagicMountain::Bot::PressurePolicy`** — stateless evaluation of PvP
  pressure decisions. Bots press rivals on factions they sell to, using a
  per-profile `pvp_aggressiveness` field (default global: `pvp_bot_aggressiveness`, 0.20).
- **`MagicMountain::Service::BotRunner`** — orchestrates the daily bot cycle.
  Called during maintenance (before day advance, only when not catching up).
  Loads bot characters, shuffles for fairness, runs each bot's day via
  `run_day()`, writing bot events to a separate transcript (`transcript_bots.jsonl`).
- **`Command::simulate`** — CLI orchestrator for the simulation loop, creates
  bot accounts/characters, drives prospecting and market phases, calls policies,
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

### 14.2 Bot Policies

Push policies (`Bot::PushPolicy`): `fixed_pushes(N)`, `instability_cap(N)`,
`stage_guard(stop_at)`, `greed(prob)`, `value_target(min)`,
`composite_and/or(policies[])`.

Sell policies (`Bot::SellPolicy`), decomposed into four decisions:
- **accept_customer**: `faction_loyalist(F)`, `hoarder`, `default`
- **should_offer_item**: `highest_offer(min_value)`, `default`
- **try_another**: `opportunist` (stop after first mismatch), `default`
- **should_accept_counter**: `default(aggression, min_pct)`, `highest_offer`
- **should_use_black_market**: `default` (never), `greedy(threshold)`, `desperate(threshold)`

Black Market evaluation gates before normal market. Bots with a
`black_market_policy` in their profile evaluate premium threshold; if met,
they dispatch through `Activity::BlackMarket` like human players.

### 14.3 Bot Strategy Profile

Bot profiles in `content/bots.yml` define: `id`, `display_name`,
`push_policy` (name + params), `sell_policy` (name), `skill_profile`,
optional `black_market_policy` and `pvp_aggressiveness`. Profiles are
selected per-bot by round-robin or weighted random (`--profile-weights`).
See `content/bots.yml` for actual definitions.

---

## 15. Transcript

JSONL (JSON Lines) file for recording game events. Each event is one JSON
object per line with a `narrative` field for human/LLM readability. Used for
simulation analysis, balance evaluation, and diagnostics. Events include:
`artifact_start`, `push`, `collapse`, `breakthrough`, `stop`, `shed_entry`,
`market_visit`, `offer`, `sale`, `sim_start`, `sim_end`, and future
`commission_triggered`, `commission_fulfilled`, `commission_expired`.

**Transcript lifecycle**: There is no request-scoped context. The transcript
is a shared JSONL file (`transcript.jsonl`) with an open file handle in the
app object. Activities write events via the API (`$self->app->transcript->log_event({...})`
or the inherited `_log_event` wrapper), which appends one JSON line with an
auto-populated `ts` (unix timestamp). No open/close/duration tracking is
performed — events are fire-and-forget.

**Transcript boundary**: Activities MAY record domain events through the
transcript API (`log_event`), but they NEVER own the transcript lifecycle
(creation, file handle, rotation) and NEVER access the file handle directly.
The file handle and lifecycle belong to the app class (`MagicMountain.pm`).
Bot events are written to a separate `transcript_bots.jsonl` file during
maintenance to keep the game transcript readable.

---

## 16. Narrative Constraints

These are non-negotiable rules for all content. The style guides in
`docs/ToneGuideForPB3K.md`, `docs/ToneGuideForFactions.md`, and
`docs/MechanicsRevealFactions.md` are authoritative for tone and voice
(also referenced from §1.1 and §7.3).

- **Player role**: The player is purely opportunistic — never a savior, never
  a villain. The game does not morally categorize the player.

- **Tone**: Grounded and observational. All characters must genuinely believe
  their actions make sense. The world should feel lived-in, not epic.

- **Presentation**: Favor implication and suggestion over outright explanation.
  Show danger ("The core screams") rather than tell danger ("The core is
  unstable"). Use concrete sensory detail.

- **Scope**: Violence and combat are not depicted. Conflict is economic,
  political, and environmental. Artifact collapse is mechanical failure, not
  human harm. PvP is economic interference, not direct harm. Faction
  characterization may include **vague threats** ("they have guns",
  "the old world was judged and found wanting") and historical violent framing,
  since these express belief systems without staging combat; depicted violence
  — present-tense, on-screen harm — remains prohibited.

- **UI verbs vs. PB3K prose**: Buttons are labeled with action verbs
  (PROSPECT, PUSH, STOP, OFFER) because they express **operator intent**
  toward the device — the operator is commanding the PB3K, not vice versa.
  The PB3K's own prose may *recommend* but should rarely *command* the operator
  (see `docs/ToneGuideForPB3K.md`). Button labels are not PB3K utterances.

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
    creation succeeds. ShedItems are liquidated at 25% of decayed_value
    via clearance sale, then forfeit at season end.

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

22. **Shed items are forfeit at season end.** They are never carried over. Before forfeit, the clearance sale liquidates unsold items at 25% of decayed_value, awarding scrap and score to the character.

23. **Estimated values are ranges, not exact figures.** The player sees
    `estimated_value_min` and `estimated_value_max`, never the precise
    `decayed_value`.

24. **Decay never destroys artifacts.** Even `fading` artifacts can be sold.
    Value may approach zero but the artifact remains.

### PvP / Rival Pressure

25. **PvP effects ride the existing §6.7 market-dynamics vocabulary** — no new
    multiplier terms are added to `_dynamic_multiplier`. Pressure applies a
    one-way clamp downward on saturation, budget, or irritation, never upward.
    Pressure never modifies push/collapse physics (preserving §17 #13).
    Unconsumed pressures are lazily purged on read after a configurable age
    threshold; no `on_maintenance` hook is added (preserving §17 #10).

### Navigation & Progressive Onboarding

26. **Tab visibility is server-authoritative.** The `/nav` response is the
    single source of truth for which tabs are visible, active, and labelled.
    JavaScript never computes tab state or constructs fragment URLs.
    Backend services (`Navigation.pm`) determine visibility from onboarding
    bitmask, AP, shed count, and activity state.

27. **Tabs are progressively revealed, never hidden.** Once a tab's
    onboarding bit is set, it stays set permanently. Returning players
    with any existing state (shed >= 1 OR sales >= 3 OR scrap >= 100)
    receive all bits at once via fast-track in `ensure_character`.

28. **New-tab notices survive page refresh.** The `pending_notices` bitmask
    is persisted on the character and cleared only when the player explicitly
    dismisses the notice card via `POST /onboarding/dismiss-notice`. Notices
    are shown one at a time, oldest first.

29. **Progressive onboarding has no gameplay effect.** The bitmask only
    controls UI visibility — it does not gate server-side endpoints,
    affect bot behavior, or modify any game mechanic. A player who
    navigates directly to a locked endpoint (e.g. `/market/begin`) will
    receive the normal response; the lock is purely navigational.

---

## 18. Activity Registration

Activity types are registered manually in `MagicMountain.pm` as explicit `has`
attributes. Each global instance is constructed with its persistence file,
content YAML path, and app reference, then calls `load_content` to parse its
YAML definitions. Adding a new activity type requires:

1. Creating the subclass in `lib/MagicMountain/Activity/`
2. Adding a `has` declaration to `MagicMountain.pm` with the constructor call
3. Adding the activity's controller routes in `buildRoutes`

There is no dynamic scanning or automatic registry. The three current activities
are `$app->prospecting`, `$app->market`, and `$app->black_market`, directly
available to controllers at request time.

---

## 19. Planned (Not Yet Implemented)

| Feature | Priority | Notes |
|---------|----------|-------|
| Commission system | Low | Faction notices, active commissions (§7.4) |
| Desperate Recruiter (underdog catch-up) | Low | Premium standing/bonus for selling to trailing factions |

---

## 20. Key Design Decisions

Design rationale is embedded in the sections that define each rule. Key
decisions are documented at these locations:

| Decision | Location |
|----------|----------|
| Two-phase architecture (HTTP vs maintenance) | §3.1–3.3 |
| Activity as persisted entity (extends Model) | §9.1, §9.3 |
| In-process maintenance timer | §3.2, §8.1 |
| Prospecting and selling as separate activities | §2, §6.5 |
| Shed as inventory buffer | §6.3, §6.4 |
| Single AP pool with weighted costs | §2 |
| Customer-first selling model | §6.5 |
| Ephemeral offers (no persistence across visits) | §6.5 invariants |
| Admin-triggered season end | §8.3 |
| Collapse = zero salvage | §6.2 step 4 |
| Score vs Scrap separation | §5.3 invariants |
| Estimated values as ranges | §6.3 step 2 |
| Three-layer faction model | §7.2 |
| YAML-driven skills | §12.3, §6.6 |
| Character deletion after SeasonRecord | §5.11 |

---

## 21. UI Design References

| Document | Purpose |
|----------|---------|
| `docs/design_bible.md` | Visual design language: palette, typography, ProspectBoy 3000 device fiction, faction iconography, panel language |
| `docs/nav_state_rules.md` | Nav state model: views, tab active/inactive rules, secondary panel mapping, context bar text |

---

## 22. Directory Layout (Top-Level)

```
magic_mountain/
├── AGENTS.md, GAME_ARCHITECTURE.md   # Specs
├── Makefile, cpanfile, magic_mountain.yml  # Build/config
├── bin/                              # Scripts (walkthrough, analyze, sim runners)
├── lib/MagicMountain/                # App code
│   ├── Activity/{Prospecting,MarketVisit,BlackMarket}.pm
│   ├── Bot/{PushPolicy,SellPolicy,PressurePolicy,BlackMarketPolicy}.pm
│   ├── Command/*.pm                  # CLI commands
│   ├── Controller/*.pm               # HTTP controllers (thin dispatch)
│   ├── Model/*.pm                    # Persistence (Character, Account, Season, ShedItem, etc.)
│   ├── Service/*.pm                  # Extracted logic (Authentication, BotRunner, RandomEvents, etc.)
│   ├── Activity.pm, Controller.pm, Model.pm  # Base classes
│   ├── Maintenance.pm, Crier.pm, ShedManager.pm, ValueTier.pm
│   └── Artifact.pm, Customer.pm, SeasonReport.pm  # View models
├── templates/                        # .ep templates (one per controller)
├── public/css/app.css, public/js/game.js
├── content/                          # YAML: artifacts, factions, skills, bots, events, flavor
├── t/                                # Test suite
├── data/                             # Runtime JSON persistence (accounts, characters, shed, etc.)
└── script/mountain                   # Entry point
```
