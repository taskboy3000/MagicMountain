# Boundary Violation Report

Generated from `.opencode/rules/` (5 rule files) and `GAME_ARCHITECTURE.md` §4/§17.

---

## Status

All 11 violations identified in the original report have been fixed (commit range `04762bb..HEAD`).
This document is kept for discussion of the remaining concerns noted below.

---

## Resolved Violations

### ✅ 1. Controller/Market.pm — Activity row creation in controller

**Fix:** Added `begin_activity()` to `Activity.pm` base class. Controllers call `$m->begin_activity($char)` instead of `$m->create(...)` + `$activity->dispatch(...)`. The `show` method still mutates `last_sale`/`last_message` on the customer object — this is display-state cleanup, not game mutation.

### ✅ 2. Controller/Prospecting.pm — Activity row creation in controller

**Fix:** Same pattern — uses `$p->begin_activity($char)` from the Activity base class.

### ✅ 3. Controller/Result.pm — Activity creation in controller

**Fix:** Uses `begin_activity()` for both prospecting and market paths. The `$char->nullCol('result')` calls remain — this is view-state cleanup (clearing the displayed outcome card), not game mutation. Consider adding `result` to the allowed UI-preference list.

### ✅ 4. Controller/Player.pm — Multi-model persistence orchestration

**Fix:** Extracted to `MagicMountain::Service::AccountDeletion`. Both `Controller::Player` and `Command::delete_account` use the service.

### ✅ 5. Model/Season.pm — `finalize()` contains extensive game logic

**Fix:** Extracted to `MagicMountain::Service::SeasonFinalizer`. The `finalize` method and `_build_highlights` helper were moved out of the model.

### ✅ 6. Model/Character.pm — Activity access, view assembly, game rules

**Fix:** Extracted to `MagicMountain::Service::CharacterView`. Methods moved: `prospecting_view()`, `market_view()`, `can_continue()`, `shed_items()`, `player_skills()`. Character.pm is now a pure data model with CRUD + invariants.

### ✅ 7. Service/SkillTraining.pm — View logic + hardcoded URL

**Fix:** Removed action-building from `skill_list()`. `Controller::Skills` now builds actions using `url_for('skills_purchase')` and passes the URL to both fragment stash and JSON response.

### ✅ 8. Service/Navigation.pm — Game rules in navigation logic

**Fix:** `build_tabs()` now accepts an `$overrides` hashref instead of encoding AP/shed rules. `Controller::Nav` computes the game-rule checks and passes precomputed tab states. Navigation exposes `base_tab_state()` for the controller to read base states.

### ✅ 9. Service/Suggestion.pm — Hardcoded game rules

**Fix:** Replaced hardcoded `2` with `$season->daily_modifier('prospect_ap_cost', 2)`. Replaced hardcoded `3` with named constant `FACTION_DESPERATION_DAYS`.

### ✅ 10. Activity.pm (base) — Domain model access from base class

**Fix:** Removed `_current_day()` method. `_log_event()` no longer sets `day`. Prospecting.pm gets day from the season directly at both call sites.

### ✅ 11. Model/Season.pm — Game constant in model

**Fix:** Removed `prospect_ap_cost()` method. Prospecting.pm calls `$season->daily_modifier('prospect_ap_cost', 2)` directly.

---

## Clean Modules (no violations found)

| Module | Notes |
|--------|-------|
| Controller.pm (base) | Compliant |
| Controller/Game.pm | Compliant |
| Controller/Market.pm | ✅ Fixed — uses `begin_activity()` |
| Controller/Prospecting.pm | ✅ Fixed — uses `begin_activity()` |
| Controller/Result.pm | ✅ Fixed — uses `begin_activity()`; `nullCol('result')` is view-state cleanup |
| Controller/Player.pm | ✅ Fixed — delegates to `AccountDeletion` service |
| Controller/Nav.pm | ✅ Fixed — computes game-rule overrides, passes to Navigation |
| Controller/Skills.pm | ✅ Fixed — builds actions with `url_for()` |
| Controller/Sessions.pm | `_clear_nav_state` saves `current_view` — allowed |
| Controller/Orientation.pm | `$char->save` for `seen_orientation` — allowed |
| Controller/OnboardingNotice.pm | `$char->save` for `pending_notices` — allowed |
| Controller/Home.pm | Pure read/display |
| Controller/Idle.pm | Pure read/display |
| Controller/Crier.pm | Pure read/display |
| Controller/Factions.pm | Pure read/display |
| Controller/Leaderboard.pm | Pure read/sort |
| Controller/Shed.pm | Filtering/sorting is UI-level |
| Controller/Reference.pm | Pure read/display |
| Controller/Root.pm | Just a redirect |
| Controller/Admin.pm | Delegates to auth_service |
| Controller/Pvp.pm | Delegates to pvp_service |
| Controller/Account.pm | Reads only |
| Controller/BlackMarket.pm | Compliant |
| Controller/Season.pm | Compliant |
| Model/Account.pm | Thin CRUD wrapper |
| Model/Character.pm | ✅ Fixed — pure data model + invariants |
| Model/Season.pm | ✅ Fixed — `finalize` extracted, `prospect_ap_cost` removed |
| Model/ShedItem.pm | Compliant |
| Activity.pm (base) | ✅ Fixed — `_current_day` removed |
| Activity/Prospecting.pm | Compliant |
| Activity/MarketVisit.pm | Compliant |
| Activity/BlackMarket.pm | Compliant |
| Service/AccountDeletion.pm | 🆕 New — handles multi-model cleanup |
| Service/CharacterView.pm | 🆕 New — view assembly for Game/Result controllers |
| Service/SeasonFinalizer.pm | 🆕 New — season-ending logic |
| Service/Navigation.pm | ✅ Fixed — receives precomputed overrides |
| Service/SkillTraining.pm | ✅ Fixed — returns data only |
| Service/Suggestion.pm | ✅ Fixed — uses `daily_modifier` + named constant |
| Service/Dominance.pm | Read-only on character data |
| Service/PvP.pm | Compliant |
| Service/RandomEvents.pm | Compliant |
| Maintenance.pm | Pure timing/callback |
| ShedManager.pm | Decay computation only |

---

## Recurring Patterns (Post-Fix Assessment)

1. ~~**Activity row creation in controllers**~~ ✅ Resolved. `begin_activity()` in the Activity base class handles create-or-get + dispatch. Controllers no longer call `create()` directly.

2. **Game rules duplicated across layers** ⚠️ Partially resolved. AP costs are no longer in `Character::can_continue()`, `Season::prospect_ap_cost()`, or `Navigation::build_tabs()`. They remain hardcoded in `CharacterView::can_continue()` (2 for prospecting, 1 for market) and `Nav::show()` (2 for prospecting, 1 for market). A single source of truth (e.g., a config-driven cost table) would eliminate the remaining duplication.

3. ~~**Model layer doing too much**~~ ✅ Resolved. `Character.pm` view methods moved to `CharacterView` service. `Season.pm::finalize` moved to `SeasonFinalizer` service.

4. ~~**View logic in services**~~ ✅ Resolved. `SkillTraining.pm` no longer builds HTML structures. Action-building moved to `Controller::Skills`.
