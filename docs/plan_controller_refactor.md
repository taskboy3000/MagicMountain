# Controller Architecture Refactoring

## Goal

Restore proper layering: controllers become thin HTTP adapters. Game logic,
navigation policy, suggestion generation, and view-model assembly live in the
domain model or dedicated services.

## Success Criteria

1. All 6 targeted controllers meet or exceed **85%** coverage (total metric).
2. Code in Game.pm `show` is reduced by at least 50% (lines of business logic).
3. Market mood/pressure calculation is defined **once** (activity model), not 3x.
4. All extracted services are independently testable (pure unit tests).
5. `AGENTS.md` updated with controller boundary rules.
6. All existing tests pass; coverage does not regress on any file.

---

## Implementation Sequence

### Phase 0 — Test Coverage Gates

Before any extraction, write tests that exercise the branches we're about to
move. These tests target the logic *in its current location* so they serve as
regression nets during extraction.

**0a — Skills.pm `purchase` edge cases**
- File: `t/skills_web.t`
- Test: at-max-level returns action_url undef, auth redirect on purchase
- Rationale: Skills.pm is already 87.7% — a small push gets it solid before
  extracting the purchase flow into a SkillService.

**0b — Market.pm `pressure_state` branches**
- File: `t/market_visit_web.t`
- Test: all 6 pressure bands (comfortable, interested, wary, strained,
  leaving, over_absolute), customer icon lookup, portrait URL construction.
- Rationale: 68.5% total coverage is the worst in the set. The pressure logic
  is duplicated in 3 places — the tests must exist before we consolidate.

**0c — Nav.pm view-resolution edge cases**
- File: `t/nav_web.t`
- Test: `X-Nav-View` header changes stored view, no-activity-override fallback,
  inactive-tab fallback, `_context_text` for view with no active activity
  (returns empty string).
- Rationale: 74.3% total, 60.6% condition coverage. View resolution has a
  non-trivial state machine with fallback chains.

**0d — Nav.pm `_build_tabs` AP/shed-count gating**
- File: `t/nav_web.t`
- Test: prospect inactive when AP=1 (needs 2), bazaar inactive when AP=0 with
  shed items, bazaar inactive when AP>=1 but no shed items.
- Rationale: Business rules embedded in controller, need branch coverage.

**0e — Home.pm `_build_suggestions` branches**
- File: `t/home_web.t`
- Test: faction-hunger suggestion triggers (days_since_purchase >= 3),
  no-AP-but-has-shed vs no-AP-no-shed vs has-AP-no-shed combinations.
- Rationale: 6 condition branches in `_build_suggestions`, only 3 covered.

**0f — Game.pm season-auto-creation edge cases**
- File: `t/game_web.t`
- Test: no archived seasons → no season_recap, config-based label prefix,
  numbered label incrementing, 0 archived seasons doesn't crash.
- Rationale: 55.2% branch coverage — season bootstrap is entirely uncovered.

**0g — Game.pm view-model assembly**
- File: `t/game_web.t`
- Test: prospecting activity idle phase → undef (vs active → data), market
  activity idle → undef, both prospecting+market idle → both undef.
- Rationale: Guards around activity type checks and phase checks.

**0h — Season.pm season resolution + standing assembly**
- File: `t/season_recap.t`
- Test: no archived seasons → 204, specific season_id lookup, player has no
  record for that season → 204, empty faction list doesn't crash.
- Rationale: 61.1% branch coverage, many early-return guards uncovered.

**0i — Season.pm narrative-parts template probing**
- File: `t/season_recap.t`
- Test: JSON endpoint includes narrative sections with correct IDs.
- Rationale: The template-existence check (line 78) is untested.

### Phase 1 — Consolidate Duplicated Logic

**1a — Market mood/pressure: single source of truth**

Public method `budget_pressure_state` on `Activity::MarketVisit` (rename
current `_budget_pressure_state`, remove leading underscore, add `display`
label). Currently returns `{ state => 'mood_*', pct => 0.xx }`. Also return
a `display` key with the uppercase label string that Nav.pm needs.

The three callers have different label needs:
- `Game.pm` and `Market.pm` use `mood_*` labels (machine state)
- `Nav.pm:_context_text` uses uppercase labels (`COMFORTABLE`, `OVER LIMIT`)
  for display text and has a different band structure (no `mood_leaving`)

Consolidate by adding `display` to the return hash so both use cases are
served from one method:

```perl
# _do_sale in MarketVisit.pm already calls this at line 752
sub budget_pressure_state ($self, $customer) {
    my $budget = $customer->{soft_budget} or return {
        state => 'mood_comfortable', display => 'COMFORTABLE', pct => 0
    };
    my $pct = ($customer->{spent_so_far} // 0) / $budget;
    my ($state, $display);
    if    ($pct <= 0.50) { $state = 'mood_comfortable'; $display = 'COMFORTABLE' }
    elsif ($pct <= 0.80) { $state = 'mood_interested';  $display = 'INTERESTED' }
    elsif ($pct <= 1.00) { $state = 'mood_wary';        $display = 'WARY' }
    elsif ($pct <= 1.10) { $state = 'mood_strained';    $display = 'STRAINED' }
    elsif ($pct <  1.20) { $state = 'mood_leaving';     $display = 'STRAINED' }
    else                 { $state = 'mood_over_absolute'; $display = 'OVER LIMIT' }
    return { state => $state, display => $display, pct => $pct };
}
```

Update callers:

| File | Change |
|------|--------|
| `Game.pm:120-128` | Replace inline with `$activity->budget_pressure_state($customer)->{state}` |
| `Market.pm:24-33` | Replace inline with `$activity->budget_pressure_state($customer)->{state}` |
| `Nav.pm:231-237` | Replace inline with `$activity->budget_pressure_state($customer)->{display}` |
| `Activity/MarketVisit.pm:635` | Remove leading underscore, add `display` to return |

Test: phase-0 pressure tests still pass (behavior preserved). **Important:**
Nav.pm context-text tests must assert display labels, not machine labels.

> **Note:** `Nav.pm:_context_text` also reads customer data
> (`faction_id`, `irritation`) and builds a display string. The plan's
> Phase 2b extracts `_context_text` into NavigationService, but the
> pressure state comes from the Activity — not from a service. The
> NavigationService will receive the pre-computed pressure state as a
> parameter, not compute it itself.

### Phase 2 — Extract Domain Services

**2a — SkillPurchase service**

- Create `lib/MagicMountain/Service/SkillTraining.pm`
- Move: skill lookup, max-level check, scrap check, scrap deduction, level
  increment from `Skills.pm:39-53` into service method `purchase($char, $skill_id)`.
- Controller `purchase` calls `$service->purchase($char, $skill_id)` and
  checks return (success/error) instead of `die`.
- New test: `t/service_skill_training.t` — pure unit test on the service.

**2b — NavigationService**

- Create `lib/MagicMountain/Service/Navigation.pm`
- Move from `Nav.pm`:
  - `_build_tabs` → `Navigation->build_tabs($char, $type, $ap, $shed_count)`
  - View-resolution logic (lines 92-120) → `Navigation->resolve_view($char, $requested_view, $type)`
  - `_context_text` → `Navigation->context_text($char, $view)`
  - `_tab_id_for` → internal helper
  - `_faction_short_name` → internal helper
- Controller `show` calls `$nav->resolve_view(...)` and iterates result.
- New test: `t/service_navigation.t` — pure unit tests on tab rules + view
  resolution + context text.

**2c — GameOrchestrator service**

- Create `lib/MagicMountain/Service/GameOrchestrator.pm`
- Move from `Game.pm`:
  - Season bootstrap (lines 30-74) → `GameOrchestrator->ensure_active_season($player_id)`
  - Character bootstrap (lines 76-93) → `GameOrchestrator->ensure_character($account_id, $season_id)`
  - Prospecting view-model assembly (100-115) → method on Prospecting Activity or GameOrchestrator
  - Market view-model assembly (116-143) → method on MarketVisit Activity
  - Shed view-model assembly (151-166) → method on ShedManager
  - Skills view-model assembly (146-149) → method on SkillTraining service
- Controller `show` calls `$orch->build_game_state($char, $season)` and
  receives a hashref for JSON response or stash keys for HTML.
- New test: `t/service_game_orchestrator.t`

**2d — SuggestionService**

- Create `lib/MagicMountain/Service/Suggestion.pm`
- Move from `Home.pm`:
  - `_build_suggestions` → `Suggestion->build($char, $season, $advisories, $shed_count)`
    (current `_build_suggestions` takes `$ap, $scrap, $shed_count, $day, $len,
    $season, $char, $advisories` — all except `$shed_count` are derivable from
    `$char` and `$season`. `$shed_count` requires a shed lookup, so either
    inject a shed store or pass the count as a parameter. The plan uses explicit
    parameter for simplicity.)
  - `_interpolate` → private helper
- Controller `show` calls `$suggestions->build(...)`. (Controller still does the
  shed lookup to get `$shed_count`, or service accepts a shed-store reference.)
- New test: `t/service_suggestion.t` — pure unit tests on all 6 branch combos.

**2e — Push more into SeasonReport**

- Move from `Season.pm` to `SeasonReport.pm`:
  - Faction name/icon lookup (lines 33-34) — `SeasonReport` already has
    `_faction_name`, but not icon. Add `_faction_icon` or include icons in
    existing faction data structure.
  - Standing-row assembly (lines 39-47) — add `->standing_rows` method.
  - Narrative-part assembly (lines 76-80) — add to `->build` or a `->narrative_elements`
    method so the controller doesn't probe template files.
- Controller `recap` then only does: resolve season → load SeasonReport →
  stash result → render.
- Existing tests in `t/season_report.t` and `t/season_recap.t` update to
  cover new methods.

### Phase 3 — Thin Controllers

After each extraction, the corresponding controller method is trimmed to:
extract HTTP params → call service → stash result → render. No business
logic, no view-model assembly, no inline calculations.

**3a — Skills.pm**
- `index`: call `SkillTraining->skill_list($char)` for action generation.
- `purchase`: call `SkillTraining->purchase($char, $skill_id)`, handle error
  vs success response. Remove all `die` — service returns success/failure.
  Preserve the `_render_action` call on success (it wraps the result with
  `csrf_token`). On error, render appropriate error JSON.

**3b — Market.pm**
- `show`: call `$activity->budget_pressure_state($customer)` for mood.
- Remove inline icon/portrait construction — push to a presenter or template.
- `_activity_action` stays (it's a valid dispatch helper).

**3c — Nav.pm**
- `show`: call `Navigation->resolve_view($char, $requested_header, $type)`.
- Remove `_build_tabs`, `_context_text`, `_tab_id_for`, `_faction_short_name`.
- Keep URL/route configuration as data hashes (those are HTTP mappings).

**3d — Game.pm**
- `show`: call `GameOrchestrator->build_state($char, $season)`.
- Remove all inline assembly blocks.
- Keep auth check and response-format dispatch (JSON vs HTML).

**3e — Home.pm**
- `show`: call `Suggestion->build($char, $season, $advisories)`.
- Remove `_build_suggestions`, `_interpolate`.

**3f — Season.pm**
- `recap`: resolve season → `SeasonReport->new(...)->build` → render.
- Remove standing assembly, icon lookup, narrative probing.

### Phase 4 — Governance

**4a — Update AGENTS.md**
- Add the "Controllers MUST NOT / SHOULD" section verbatim from `fb.md`.
- Add note on test-before-extract workflow.

**4b — Update `.gitignore` if needed**

**4c — Document extraction pattern in AGENTS.md**
- Add: "Extracting controller logic: write tests for the function in situ,
  extract to service, verify same tests pass, then thin controller."

---

## Dependencies & Sequencing

```
Phase 0 (tests) ─────────────────────┐
                                     │
                                     ├─► Phase 1 (mood dedup)
                                     │       │
                                     │       ├─► Phase 3b (Market thin)
                                     │       ├─► Phase 2b (NavService)  ──► Phase 3c (Nav thin)
                                     │       └─► Phase 2c (GameOrch)    ──► Phase 3d (Game thin)
                                     │
                                     ├─► Phase 2a (SkillService) ──► Phase 3a (Skills thin)
                                     ├─► Phase 2d (Suggestion)  ──► Phase 3e (Home thin)
                                     └─► Phase 2e (SeasonReport)──► Phase 3f (Season thin)
                                                                       │
                                                                       └──► Phase 4 (Governance)
```

Phase 0 tasks are independent (parallel). Phase 1 **must complete before**
Phase 3b, 2b, and 2c because it modifies the same inline pressure logic
that those steps also touch. Phase 2a, 2d, 2e are independent of Phase 1
(they touch different code). Each service extraction pairs with its
controller thinning (sequential: extract first, then thin).

---

## Verification

Each step must pass:
1. `prove -l t/` — full test suite
2. `make cover && make report` — no coverage regression on any `lib/*.pm`
3. `bash bin/smoke_test_endpoint GET /<resource>?_format=fragment` — for
   affected endpoints
4. `perl bin/walkthrough` — end-to-end game loop

## Resolved Decisions

**1. DI pattern: Pass `$app` ref** — Services get `$self->app` access like
Activities do. Simplifies wiring at the cost of coupling to the full app.
Pure unit tests will use `Test::Mojo` integration context.

**2. SeasonReport template probing: Data-driven list** — Eliminate the
filesystem check. SeasonReport defines known section template IDs as data.
If a section needs a template but none exists, it logs a warning and skips.

**3. Flavor/config in Game.pm: Stay in controller** — `_unit_status` and
`factions_data` are static config reads, not game logic. Controller keeps them.

**4. Nav context text: Stay in controller** — `_context_text` is display
formatting, not navigation policy. Stays in controller. Pressure state comes
from Activity method via `$self->app->market->get($id)->budget_pressure_state(...)`.

## Risks

- **Season.pm narrative-part template probing** (line 78: `-e $self->app->home->child(...)`)
  is fragile. It checks filesystem for template existence. This should be
  replaced with a data-driven approach (list of known section templates) or
  moved entirely into SeasonReport.
- **Game.pm season auto-creation** has config-dependent branching (label
  prefix, day length, EOD hour) — test with mock config.
- **Nav.pm view resolution** has 5+ fallback rules that interact. Pure unit
  tests on the extracted function are essential to prevent regressions.
- **Market.pm `_activity_action`** is a helper used by 5 action endpoints.
  Don't touch it — it's a valid dispatch pattern. Only `show` needs thinning.
