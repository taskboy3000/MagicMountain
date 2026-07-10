# Boundary Violation Report

Generated from `.opencode/rules/` (5 rule files) and `GAME_ARCHITECTURE.md` §4/§17.
No code changes — exploration only.

---

## Critical Violations

### 1. Controller/Market.pm — Activity row persistence + creation in controller

**File:** `lib/MagicMountain/Controller/Market.pm:35,96`
**Rules violated:** Controllers must NOT persist game state (activity rows); must NOT create activity rows

Line 35: The `show` method mutates customer data (`last_sale`, `last_message`) and calls `$activity->save` on the activity row. This is game-state persistence in a read-only view handler.

Line 96: The `_activity_action` helper calls `$m->create(...)` to construct a new activity row when none exists. Activity creation belongs inside the activity's `begin` handler or a service.

### 2. Controller/Prospecting.pm — Activity row creation in controller

**File:** `lib/MagicMountain/Controller/Prospecting.pm:90`
**Rules violated:** Controllers must NOT create activity rows

Same pattern as Market.pm: `$p->create(...)` when no pending activity exists. Activity creation should be inside the activity's `begin` handler.

### 3. Controller/Result.pm — Game-state persistence + activity creation

**File:** `lib/MagicMountain/Controller/Result.pm:41-43,56,59,63`
**Rules violated:** Controllers must NOT persist game state; must NOT create activity rows

Lines 41-43, 56: `$char->nullCol('result')` clears the `result` column, which contains game-state data (outcome, artifact value, sale details). The `result` column is not in the allowed UI-preference list (`current_view`, `seen_orientation`, `settings_muted`, `pending_notices`).

Lines 59, 63: Directly creates activity rows (`$self->app->prospecting->create(...)`, `$self->app->market->create(...)`) and dispatches them. Activity lifecycle belongs to the activity system.

### 4. Controller/Player.pm — Multi-model persistence orchestration

**File:** `lib/MagicMountain/Controller/Player.pm:48-54`
**Rules violated:** Controllers must NOT orchestrate multi-model persistence

Iterates all characters for an account, deletes each one, then deletes the account — all in a single controller action. Should delegate to a service.

### 5. Model/Season.pm — `finalize()` contains extensive game logic + character data

**File:** `lib/MagicMountain/Model/Season.pm:23-132`
**Rules violated:** Model::Season must NEVER contain per-player character data or game logic

The `finalize` class method loads all characters, sorts by score, computes clearance sales at 25%, awards scrap/score, creates SeasonRecords with skill/faction snapshots, deletes characters, and writes faction snapshots. This is a season-ending activity that should live in a service or command, not a model method.

### 6. Model/Character.pm — Activity access, view assembly, game rules

**File:** `lib/MagicMountain/Model/Character.pm:74-152`
**Rules violated:** Model::Character must NEVER contain game math, artifact logic, or state mutation outside of CRUD

Three violations:
- `prospecting_view()` (line 74): Accesses `$self->app->prospecting`, reads raw artifact hash, constructs view data. Knows about prospecting activity internals.
- `market_view()` (line 93): Accesses `$self->app->market`, calls `budget_pressure_state()`, constructs customer view hash. Knows about market activity internals.
- `can_continue()` (line 138): Encodes AP cost thresholds (prospecting=2, market=1) and queries shed items. Game rules in the model layer.

---

## High Severity

### 7. Service/SkillTraining.pm — View logic + hardcoded URL

**File:** `lib/MagicMountain/Service/SkillTraining.pm:41-60`
**Rules violated:** Service::SkillTraining must NEVER contain view logic or URL construction

Builds HTML button structures with CSS classes, disabled states, and data attributes (view logic). Hardcodes `/skills/purchase` instead of using `url_for` (breaks behind reverse proxy).

### 8. Service/Navigation.pm — Game rules in navigation logic

**File:** `lib/MagicMountain/Service/Navigation.pm:56-89`
**Rules violated:** Service::Navigation must NEVER contain game rules

Encodes AP thresholds (bazaar requires AP >= 1, prospecting requires AP >= 2) and shed-item requirements. Navigation should receive precomputed tab states, not re-encode game costs.

### 9. Service/Suggestion.pm — Hardcoded game rules

**File:** `lib/MagicMountain/Service/Suggestion.pm:23,58`
**Rules violated:** Service::Suggestion must NEVER contain game rules

Line 23: Hardcodes prospecting AP cost (2). Line 58: Hardcodes faction desperation threshold (3 days). These are game-design constants duplicated from other layers.

---

## Medium Severity

### 10. Activity.pm (base) — Domain model access from base class

**File:** `lib/MagicMountain/Activity.pm:70-77`
**Rules violated:** Activity base class must NEVER contain expedition-specific logic

The `_current_day` method reaches into `$self->app->seasons`, loads the model collection, filters for active status, and reads the `day` column. This is season-domain knowledge that couples every activity subclass to the seasons model. The current day should be passed in by the caller.

### 11. Model/Season.pm — Game constant in model

**File:** `lib/MagicMountain/Model/Season.pm:19-21`
**Rules violated:** Model::Season must NEVER contain game logic

`prospect_ap_cost()` returns a default of 2 — a game-design constant encoded in the model. The default belongs in the Prospecting activity or configuration.

---

## Clean Modules (no violations found)

| Module | Notes |
|--------|-------|
| Controller.pm (base) | Compliant |
| Controller/Game.pm | Compliant |
| Controller/Nav.pm | `$char->save` for `current_view`/`settings_muted` is now explicitly allowed |
| Controller/Sessions.pm | `_clear_nav_state` saves `current_view` — allowed |
| Controller/Orientation.pm | `$char->save` for `seen_orientation` — allowed |
| Controller/OnboardingNotice.pm | `$char->save` for `pending_notices` — allowed |
| Controller/Home.pm | Pure read/display |
| Controller/Idle.pm | Pure read/display |
| Controller/Crier.pm | Pure read/display |
| Controller/Factions.pm | Pure read/display |
| Controller/Leaderboard.pm | Pure read/sort |
| Controller/Skills.pm | Delegates to SkillTraining service |
| Controller/Shed.pm | Filtering/sorting is UI-level |
| Controller/Reference.pm | Pure read/display |
| Controller/Root.pm | Just a redirect |
| Controller/Admin.pm | Delegates to auth_service |
| Controller/Pvp.pm | Delegates to pvp_service |
| Controller/Account.pm | Reads only |
| Controller/BlackMarket.pm | Compliant |
| Controller/Season.pm | Compliant |
| Model/Account.pm | Thin CRUD wrapper |
| Model/ShedItem.pm | Compliant |
| Activity/Prospecting.pm | Compliant (internal math not exposed in view) |
| Activity/MarketVisit.pm | Compliant (no prospecting logic) |
| Activity/BlackMarket.pm | Compliant (no MarketVisit logic) |
| Service/Dominance.pm | Read-only on character data |
| Service/PvP.pm | Compliant |
| Service/RandomEvents.pm | Compliant |
| Maintenance.pm | Pure timing/callback |
| ShedManager.pm | Decay computation only |

---

## Recurring Patterns

1. **Activity row creation in controllers** (Market.pm, Prospecting.pm, Result.pm): The `create-then-dispatch` pattern should be inside the activity's `begin` handler, not in the controller.

2. **Game rules duplicated across layers**: AP costs appear in `Character::can_continue()`, `Season::prospect_ap_cost()`, `Navigation::build_tabs()`, and `Suggestion.pm`. No single source of truth.

3. **Model layer doing too much**: `Character.pm` has view assembly methods (`prospecting_view`, `market_view`) and game rules (`can_continue`). `Season.pm::finalize` is a 110-line activity masquerading as a model method.

4. **View logic in services**: `SkillTraining.pm` builds HTML button structures. Services should return data, not UI-ready structures.
