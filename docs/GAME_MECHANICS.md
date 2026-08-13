# Game Mechanics

Data lifecycle reference for the MagicMountain game engine.

## Structures

### Season (`MagicMountain::Model::Season`)

Persisted in `data/seasons.json`. One active season at a time.

| Column | Type | Description |
|--------|------|-------------|
| `faction_state` | hashref | Per-faction influence, daily_intake, days_since_purchase, artifacts_received, intake_by_trait, name |
| `faction_climate` | hashref | Day's climate effects — dominant_faction, prospecting biases, market deltas, narrative texts |
| `crier_message` | string | Daily narrative generated at maintenance |
| `crier_snapshot` | hashref | Copy of faction_state at moment crier_message was generated |
| `daily_modifiers` | hashref | Global events that modify AP cost, value, instability for one day |
| `global_event_text` | string | Active global event narrative (priority over crier) |
| `day` | int | Current day number (1-based) |
| `length` | int | Season length in days (default 30) |

### Character (`MagicMountain::Model::Character`)

One per player per season. Persisted in `data/characters.json`.

| Key | Description |
|-----|-------------|
| `action_points` | Available actions for the day |
| `scrap` | Currency |
| `score` | Leaderboard score |
| `pending_activity_id` | FK to active activity row |
| `skills` | Hash of skill_id → level |
| `standing` | Hash of faction_id → standing |
| `faction_sales` | Hash of faction_id → total sales to that faction |
| `shed_items` | (accessed via shed model by char_id) |

### Activity (`MagicMountain::Activity` and subclasses)

Persisted in `data/activities.json`. State machine per activity type.

| Column | Description |
|--------|-------------|
| `char_id` | FK to character |
| `type` | Discriminator: `prospecting`, `market_visit`, `pawn` |
| `phase` | Current state: `idle`, `processing`, `negotiating`, `result` |
| `artifact` | Live artifact state during prospecting (hashref) |
| `customer` | Live customer state during market (hashref) |

### Shed Item (`MagicMountain::Model::Shed`)

Persisted in `data/shed.json`. One row per artifact waiting to be sold.

| Key | Description |
|-----|-------------|
| `char_id` | Owner |
| `artifact_id` | Spec ID |
| `original_value` | Value when stopped/breakthrough |
| `decayed_value` | Current value after decay |
| `condition` | `fresh`, `settling`, `fading` |
| `behaviors` | Trait list (used for faction matching) |
| `decay_modifiers` | fresh_multiplier, settling_multiplier, fading_multiplier, settling_day, fading_day |

## Data Lifecycle

### Daily Maintenance

Triggered at `end_of_day_hour` (default 0 = midnight) by the daemon's 60-second timer, or manually via `perl -Ilib script/mountain advance-day`.

**Order of operations** (`MagicMountain::Maintenance`, `MagicMountain::Service::DailyMaintenance`):

The maintenance window has two phases: a **bot window** (external subprocess) and a **rollover** (in-process):

**Bot Window Phase** (opens at `end_of_day_hour`):

1. `Maintenance::dailyMaintenance` sees maintenance is due, calls `Service::DailyMaintenance::open_bot_window`
2. Sets `bot_window_open = 1`, advances `next_run` to tomorrow
3. Spawns `bot-turn` command as a non-blocking subprocess (`Mojo::IOLoop->subprocess`)
4. While the window is open:
   - `in_maintenance` stays 0 — normal game operation continues
   - Bot logins require `X-Bot-Service-Token`; non-bot logins get HTTP 503 (token gate in `Sessions::_build_session`)
5. When the subprocess exits (or deadline timer fires), `_rollover` runs

**Rollover Phase** (when last bot finishes or deadline expires):

1. `_backup_data` — copy all JSON data files to date-stamped backup directory
2. `in_maintenance(1)` — write routes return HTTP 503
3. `on_maintenance` callback runs:
   - Clear `daily_modifiers`, `global_event_text`
   - Advance `day` counter, save
   - Refresh AP for all characters
   - Apply shed decay (items age: fresh→settling→fading)
   - Reset `faction_state.daily_intake = 0`, increment `days_since_purchase`
   - **Calculate faction climate** — `Dominance::calculate_climate`
   - Draw and apply global event (may modify faction_state further)
   - **Generate crier message** — from faction climate text and faction_state diffs
   - Snapshot faction_state into `crier_snapshot`
   - Write faction snapshots to `faction_snapshots.json`
   - Store modified faction_state
   - Check if season should end (day > length)
4. `in_maintenance(0)` — normal operation resumes
5. `bot_window_open = 0` — bot logins reopened

**Manual advance-day**: `advance-day` command shells out to `bot-turn` synchronously (waiting for all bots), then runs the rollover phase. If bots fail, the day still advances (graceful degradation).

**Deadline valve**: If bots have not finished within `maintenance_bot_deadline_minutes` (default 10), the rollover runs anyway and that day's bots are skipped. This prevents a stalled bot from halting the season.

### Faction Influence

Faction influence is the core competitive mechanic. Each faction competes for dominance.

**How influence is gained**: When a player sells an artifact to a faction, the faction's influence increases by the artifact's value. The sale happens in `MarketVisit.pm` during the `offer` handler.

**Where influence lives**: `$season->getCol('faction_state')->{$faction_id}{influence}` — a mutable integer updated in-place during market sales.

`faction_state` is the **source of truth** for who is winning. It's the only authoritative record of influence.

### Faction Climate

**Calculated once per day** at maintenance by `Dominance::calculate_climate`.

**What it computes** (`Dominance.pm:401-452`):
- `dominant_faction`, `dominant_faction_name` — leader from faction_state
- `intensity`, `intensity_label` — tier: contested|leading|strong|dominant
- `dominance_margin` — influence gap between #1 and #2
- `prospecting.draw_biases` — trait weights scaled by intensity factor
- `prospecting.starting_instability_mod` — instability shift scaled by factor
- `market.budget_delta`, `mood_delta`, `patience_delta`, etc. — buyer behavior shifts
- `market.buyer_trait_biases` — traits the market pays premium for
- `market.market_summary` — prose description of market conditions
- `town_crier`, `crier_text` — faction-themed narrative text
- `finds_summary`, `has_meaningful_finds` — prose about prospecting biases
- `banned_traits` — traits refused by the dominant faction
- `mountain_positions`, `mountain_height`, `mountain_raster` — visualization data

**When it's read**:
- Prospecting draw weights (`dominance_service.draw_biases`)
- Prospecting starting instability (`dominance_service.starting_instability_mod`)
- Market customer budgets/moods (`dominance_service.budget_delta`, etc.)
- Shed item restrictions (checking `banned_traits`)
- Dashboard display (`faction_climate.dominant_faction_name`, `finds_summary`, `market_summary`)
- Mountain chart (`faction_climate.mountain_positions`, `mountain_raster`)
- Suggestions service (`has_meaningful_finds`, `market.buyer_trait_biases`)

### Mid-Day Leader Change

`faction_state` can change during the day as players sell artifacts. This may cause the leader to change.

The **only code** that updates `faction_climate` mid-day is `ensure_mountain_data` (`Dominance.pm:386-411`), called when the factions/leaderboard tab is loaded. It updates display fields (`dominant_faction`, `dominant_faction_name`, `mountain_positions`, `intensity_label`, `banned_traits`) but preserves frozen gameplay coefficients.

**Invariant**: Gameplay coefficients (`prospecting`, `market.*`) are set once at maintenance and never change mid-day. The mountain chart and dashboard narrative are visualization-only state.

| Field | Frozen at maintenance? | Updated mid-day? |
|-------|----------------------|-----------------|
| `prospecting.draw_biases` | yes | no |
| `prospecting.starting_instability_mod` | yes | no |
| `market.budget_delta` etc. | yes | no |
| `market.buyer_trait_biases` | yes | no |
| `banned_traits` | yes (if factor>0) | yes (by ensure_mountain_data) |
| `dominant_faction` | yes | yes |
| `dominant_faction_name` | yes | yes |
| `intensity_label` | yes | yes |
| `mountain_positions` | yes | yes |
| `town_crier`, `crier_text` | yes | yes (by _refresh_narrative) |
| `finds_summary`, `market_summary` | yes | yes (re-derived from frozen coeffs) |

### Crier Message

Generated at maintenance by `Crier::generate` (`Crier.pm:35-136`).

**Priority order** (highest first):
1. `global_event_text` — active global event narrative (overrides everything)
2. `faction_climate.crier_text` — static faction-themed text (unless contested)
3. `faction_dominance` — triggered when a new faction seizes the lead
4. `faction_surge` — faction gained influence
5. `milestone` — faction reached artifact count threshold
6. `faction_slump` — faction received zero artifacts
7. `season_opening` / `daily_progress` — day-1 or time-of-season text
8. `generic` — fallback

Stored as `crier_message` on the season and `faction_climate.crier_text` inside climate.

### Activity State Machine

All activities share a base dispatch in `Activity.pm`.

```perl
$activity->dispatch($char, $action_name, %params)
```

1. Reads current `phase` from row
2. Looks up valid transitions for that phase
3. Dies with "illegal transition" if action not allowed
4. Calls `$self->$action_name($char, %params)`

**`begin_activity` entry point** (`Activity.pm:88-101`):
1. Checks if character has a `pending_activity_id`
2. If yes and that activity's phase is not `idle` → deletes stale activity, clears pending_activity_id
3. Creates new activity
4. Dispatches `begin`

| Activity Type | Phases | Transitions |
|---------------|--------|-------------|
| Prospecting | idle → processing | begin (2 AP), push (0), stop (0), resolve_event (0) |
| Market | idle → negotiating | begin (1 AP), offer (0), send_away (0), accept_counter (0), stand_pat (0) |
| Pawn | idle → result → idle | offer (1 AP), dismiss (0), offer_next (0) |

### Shed Decay

Applied by `ShedManager::apply_decay` during maintenance.

Items age by `condition` each day:
- `fresh` → `settling` after `settling_day` (default 2)
- `settling` → `fading` after `fading_day` (default 5)
- Value is multiplied by `fresh_multiplier`, `settling_multiplier`, or `fading_multiplier` to produce `decayed_value`

### Bot System

Bots are multi-day automated players. Created at season start with bot profiles.

**Profile-driven behavior** (`Bot::Routine`):
1. **Prospect phase**: begin → push loop (with PushPolicy) → stop/collapse/breakthrough
2. **Market phase**: begin → accept/send_away customer → offer loop (with SellPolicy)
3. **Pawn phase**: offer banned items (with PawnPolicy)
4. **Skill phase**: purchase skills (with SkillPolicy)
5. **PvP phase**: apply pressure (with PressurePolicy)

Bot agents make real HTTP requests to `localhost:$port` during maintenance. Game state changes happen through the same controllers that human players use.

### Transcript System

Events logged to `data/transcript.jsonl` via `$self->app->log_event` or `$activity->_log_event`. Used for:
- Season reports (`Command/report.pm`)
- LLM-generated season summaries
- Bot auditing

**Event types** include: `artifact_start`, `push`, `stop`, `collapse`, `breakthrough`, `shed_entry`, `market_visit`, `offer`, `sale`, `send_away`, `player_action`, `faction_snapshot`, `random_event`, event outcomes, skill purchases.

**Key invariant**: Bot events MUST go to the main transcript (not a separate file) to get accurate per-player metrics. The `transcript_cb` parameter was removed from `MagicMountain.pm` to enforce this — all events flow through `log_event`.
