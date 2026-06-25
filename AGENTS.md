# Magic Mountain — AGENTS.md

> Reimplementation of Magic Mountain on a clean foundation.

---

## What Is This?

**Magic Mountain** is a multiplayer, seasonal push-your-luck web game. Players
extract strange artifacts from a mysterious mountain, destabilize ("push") them
for greater value (risking catastrophic collapse), and sell to competing
factions. Each ~30 day season is a tournament: highest cumulative score wins.

**Core loop**: Prospect → Push (repeat) → Stop → Sell at Bazaar → Repeat until
out of AP → Day rollover → Season ends.

This is a ground-up reimplementation following the architecture spec in
`GAME_ARCHITECTURE.md`.

---

## Directory Layout

```
magic_mountain/
├── AGENTS.md                      # This file — project guide for AI agents
├── GAME_ARCHITECTURE.md           # Target architecture spec (authoritative)
├── FUTURES.md                     # Planned work beyond current implementation
├── Makefile                       # test, cover, indent targets
├── cpanfile                       # Perl dependencies (Mojolicious, YAML::XS, etc.)
├── magic_mountain.yml             # App config (secrets, session_timeout_minutes, end_of_day_hour)
│
├── lib/
│   ├── MagicMountain.pm              # Mojolicious app: routes, helpers, attributes
│   └── MagicMountain/
│       ├── Controller.pm                # Base controller
│       ├── Controller/Root.pm           # Gateway redirect (GET / → /login or /game)
│       ├── Controller/Sessions.pm       # Login/logout, session management
│       ├── Controller/Player.pm         # Current player info (GET /player)
│       ├── Controller/Game.pm           # Game state page (GET /game)
│       ├── Controller/Prospecting.pm    # Prospecting actions (begin, push, stop)
│       ├── Controller/Market.pm         # MarketVisit actions (begin, offer, send_away)
│       ├── Controller/Shed.pm           # Shed inventory listing
│       ├── Controller/Skills.pm         # Skill purchase endpoint
│       ├── Controller/Leaderboard.pm    # Season leaderboard
│       ├── Model.pm                     # Base persistence class (JSON file CRUD, UUID, find)
│       ├── Model/Account.pm             # Player accounts (username, password)
│       ├── Model/AuditLog.pm            # JSONL event log
│       ├── Model/Character.pm           # Per-season character (name, score, AP, skills)
│       ├── Model/Season.pm              # Season config and state
│       ├── Model/Session.pm             # Server-side session tracking
│       ├── Model/HallOfFame.pm          # Hall of Fame entries
│       ├── Model/ShedItem.pm            # Shed artifact inventory row
│       ├── Model/ArtifactDisposition.pm # Per-sale permanent record
│       ├── Model/Transcript.pm          # Game event log
│       ├── Model/SeasonRecord.pm        # Post-season archive
│       ├── Activity.pm                  # Base class for state-machine activities
│       ├── Activity/Prospecting.pm      # Artifact draw, push/collapse/breakthrough, stop
│       ├── Activity/MarketVisit.pm      # Customer generation, negotiation, sale
│       ├── Maintenance.pm               # In-process daily maintenance timer
│       ├── ShedManager.pm               # Artifact decay logic
│       ├── Crier.pm                     # Town Crier narrative generation
│       └── Command/
│           ├── create_account.pm        # CLI: create-account
│           ├── delete_account.pm        # CLI: delete-account
│           ├── disable_account.pm       # CLI: disable-account
│           ├── list_accounts.pm         # CLI: list-accounts
│           ├── advance_day.pm           # CLI: advance-day (manual maintenance trigger)
│           ├── create_season.pm         # CLI: create-season
│           ├── end_season.pm            # CLI: end-season (finalization)
│           └── simulate.pm              # CLI: run bot simulation
│
├── templates/
│   ├── layouts/default.html.ep    # Bootstrap 5 layout wrapper
│   ├── sessions/new.html.ep       # Login form
│   └── game/show.html.ep          # Authenticated home page with game state
│
├── public/css/                    # Frontend assets (placeholder)
├── public/js/                     # Frontend assets (placeholder)
│
├── content/                       # YAML content definitions
│   ├── prospecting.yml            # Artifact specs and weights
│   ├── factions.yml               # Faction definitions and interests
│   └── skills.yml                 # Skill tree and costs
│
├── t/                             # Test suite (29 files, 253 tests)
│   ├── model.t                    # Base Model class tests
│   ├── model_account.t            # Account model tests
│   ├── model_character.t          # Character model tests
│   ├── model_character_invariants.t
│   ├── model_season.t             # Season model tests
│   ├── model_shed_item.t
│   ├── model_artifact_disposition.t
│   ├── model_hall_of_fame.t       # Hall of Fame model tests
│   ├── model_delete.t
│   ├── model_validate.t
│   ├── model_save_table_edit.t
│   ├── session.t                  # Session lifecycle tests
│   ├── login.t                    # Login flow integration tests
│   ├── activity.t                 # Activity base class tests
│   ├── activity_prospecting.t     # Prospecting unit tests
│   ├── market_visit.t             # MarketVisit unit tests
│   ├── prospecting_web.t          # Prospecting web integration tests
│   ├── market_visit_web.t         # MarketVisit web integration tests
│   ├── shed.t                     # ShedManager tests
│   ├── decay.t                    # Artifact decay tests
│   ├── crier.t                    # Crier narrative tests
│   ├── maintenance.t              # Daily maintenance tests
│   ├── transcript.t               # Transcript tests
│   ├── faction_state.t            # Faction state tests
│   ├── leaderboard.t              # Leaderboard tests
│   ├── end_season.t               # Season finalization tests
│   ├── season_recap.t             # Season recap display tests
│   ├── bot_simulate.t             # Bot simulation tests
│   └── command_advance_day.t      # advance-day CLI tests
│
└── script/mountain                # App entry point: perl script/mountain <command>
```

---

## Current Status: Complete Core Implementation

The entire core game loop is implemented and tested:

| Layer | Status | Files |
|-------|--------|-------|
| App shell | Done | `MagicMountain.pm`, `Controller.pm`, `Controller/Root.pm` |
| Persistence | Done | `Model.pm` + all Model::* subclasses |
| Auth/Sessions | Done | `Controller/Sessions.pm`, `Controller/Player.pm`, `Model/Session.pm` |
| CLI commands | Done | 8 commands (account management, season lifecycle, simulation) |
| Web UI | Done | Login, game state, prospecting, market, shed, skills, leaderboard |
| Prospecting | Done | `Activity/Prospecting.pm`, `Controller/Prospecting.pm` |
| MarketVisit | Done | `Activity/MarketVisit.pm`, `Controller/Market.pm` |
| Shed / Decay | Done | `ShedManager.pm`, `Model/ShedItem.pm`, `Controller/Shed.pm` |
| Daily Maintenance | Done | `Maintenance.pm` (in-process timer, AP refresh, decay, Crier) |
| Faction System | Done | YAML-driven factions, standing, influence, Crier |
| Skills | Done | `Controller/Skills.pm`, `content/skills.yml` |
| Season Lifecycle | Done | CLI create/end, auto-creation, recap, Hall of Fame |
| Bot Simulation | Done | `Command/simulate.pm`, `t/bot_simulate.t` |

### Known Gaps

See `FUTURES.md` for detailed categorization. Summary:

| Item | Status |
|------|--------|
| Game activities (Prospecting, Market) | **Done** |
| Daily maintenance | **Done** |
| Factions + Crier | **Done** |
| Season finalization | **Done** (CLI only, no web UI) |
| Bot simulation | **Done** (single hardcoded strategy) |
| Commission system (§7.3) | Not implemented |
| Market dynamics (§6.7) | **Done** |
| MarketVisit Enhancements (§6.5) | **Done** (counter-offers + multi-item, both gated by config, default off) |
| MariaDB migration | Deferred — JSON persistence writes entire table on every `save()`. This caps simulations at ~500 total bot-days for reasonable runtime. See FUTURES.md for details. |
| CSRF / rate limiting / password auth | Deferred for alpha |

---

## Running the App

```bash
# Start dev server
perl -Ilib script/mountain daemon

# CLI commands
perl -Ilib script/mountain create-account --name alice
perl -Ilib script/mountain list-accounts
perl -Ilib script/mountain simulate --players 10 --days 5
perl -Ilib script/mountain end-season
```

### RAM Disk for Simulation Speed

The JSON persistence layer writes the entire table on every `save()`, so
simulation I/O is a bottleneck — especially on a VM. Use a tmpfs RAM disk:

```bash
# One-time setup (after reboot):
sudo bin/setup_ramdisk

# Run simulations with TMPDIR pointing at the ramdisk:
TMPDIR=/mnt/ramdisk perl -Ilib script/mountain simulate --count 10 --days 14
```

This redirects File::Temp's tempdir (where sim data lives) to RAM instead of
disk, which significantly speeds up simulation runs.

### Batch Simulation Runner

```bash
# Run 20 seeds of 2-bot default config (fast sanity check, ~1 min)
TMPDIR=/mnt/ramdisk perl bin/run_many --bots 2 --days 30 --seeds 1-20

# Run 100 seeds of 6-bot both config (takes a while)
TMPDIR=/mnt/ramdisk perl bin/run_many --bots 6 --days 30 --seeds 1-100 --config both

# Other configs: default, counter_offers, multi_item, both
```

Shows seed-by-seed progress with ETA, then aggregates win counts and average
scores per bot personality.

## Testing

```bash
# Run all tests
prove -l t/

# Run specific test
prove -lv t/prospecting_web.t

# Run coverage analysis (run before every commit)
make cover

# View coverage summary
make report
```

Test coverage must stay at or above **85%**. Run `make cover && make report`
before every commit to verify. `make cover` runs the full test suite under
Devel::Cover instrumentation (takes a while), then `make report` displays
the summary.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Web framework | Mojolicious 9.40+ (Perl) |
| Persistence | JSON files with atomic write-via-temp-file + flock |
| Config | YAML (`magic_mountain.yml`, `content/*.yml`) |
| Frontend | Bootstrap 5.3 CDN, vanilla JS |
| Testing | Test::More, Test::Mojo |
| Perl | 5.28+ with signatures (`-signatures`) |

---

## Key Conventions

- **Models**: Subclass `MagicMountain::Model`. Declare `columns`, use
  `getCol`/`setCol` accessors. Persist with `save()`, load with `load()`,
  query with `find()`.
- **Activities**: Subclass `MagicMountain::Activity`. Declare `transitions`,
  implement one handler per action. Dispatch via `$activity->dispatch($char, $action)`.
  Handlers own all persistence (saves, deletes, FK management).
- **Controllers**: Return JSON. Use `$self->session(playerId => ...)` for auth.
  Dumb pipes — call `dispatch`, pipe `view` to template.
- **Commands**: Subclass `Mojolicious::Command`. Register namespace in
  `MagicMountain.pm`.
- **Config**: Add defaults in `MagicMountain.pm` → `defaultConfig`. Override
  in `magic_mountain.yml`. `end_of_day_hour` is 0–23 (midnight default).
- **Tests**: Use `Test::Mojo` for integration. Use `tempdir(CLEANUP => 1)`
  with `$ENV{MM_DATA_DIR}` for isolated state.
- **Test data seeding**: Never write JSON files directly (`write_file` to
  `*.json`). Always use Model objects (`->create`, `->save`) to set up
  test state. This ensures tests work across persistence backends and
  exercises the Model API.
- **Formatting**: Run `make indent && make clean` before every commit to ensure
  consistent perltidy formatting.
- **Fix bad patterns on sight**: LLMs reproduce the patterns they see in the
  current codebase. When you encounter a suboptimal pattern (e.g., raw JSON
  writes, copy-pasted boilerplate, inconsistent naming, missing tests), fix it
  immediately rather than replicating it or leaving a TODO. Every bad pattern
  left in place compounds — it becomes the template for the next change.
- **No automatic commits**: Never commit without being asked. Only commit when
  the user explicitly instructs it. This prevents surprise history changes.
- **Frontend-backend sync**: Every backend feature that changes API response
  shapes or adds new activity results must include a frontend update
  (`public/js/game.js`) and a web integration test (`t/*_web.t`) that exercises
  the full round-trip from button click to response rendering. The frontend
  update must handle all new API result types inline rather than falling back
  to `loadGame()`. Add the frontend wiring as a task in the same session as
  the backend change — never ship a backend feature without the corresponding
  JS handler.
- **New result types**: When adding a new `result` string to an Activity handler
  (e.g. `'sold_more'`, `'over_budget'`), read the full set of possible result
  values back to the user before finishing the session so they can confirm the
  API shape before any frontend work starts.
- **Smoke-test after template/controller changes**: After creating or modifying
  a template or controller that serves a fragment endpoint, run
  `bash bin/smoke_test_endpoint GET /<resource>?_format=fragment` before declaring the
  task done. The script handles login, CSRF, and character creation. A 500
  response means the template failed to compile. Run `bash bin/smoke_test_endpoint GET /game`
  after any route or layout change to verify the full page still loads.

  **Expected status codes**: Fragment endpoints return `200` when data is available
  (an active activity for prospecting/market, any character for idle/player/skills/factions,
  items in shed for shed, rankings for leaderboard) and `204` when no data is available.
  A smoke test must verify the status code matches the expected state — a 200 when you
  expect data or a 204 when you expect none is part of the validation. The script
  uses a unique account per run so leftover state never bleeds between tests.
- **Phase workflow**: Every phase that modifies backend behaviour (API responses,
  fragment templates, activity handlers) or frontend wiring (fragment fetchers,
  result handlers) must include a smoke-test step. Run `bin/smoke_test_endpoint` on
  each affected fragment endpoint to confirm the template compiles (no 500), then
  manually exercise the round-trip via curl for POST actions to confirm refetch keys
  and inline handlers work.
- **Coverage**: Run `make cover && make report` before every commit. Coverage
  for all `lib/*.pm` files must stay at or above **85%** (statement coverage).
  If you add new code without tests, coverage drops and the commit should be
  blocked. Test script (`.t`) and test helper coverage is not part of this
  threshold.
- **Balance checks**: Run `make check-coverage` for fast static validation
  that all faction interest tags have adequate artifact coverage. Run
  `make check-loyalist` (~15s) to verify each faction can support a viable
  loyalist strategy via simulation. Run these when modifying
  `content/prospecting.yml` or `content/factions.yml`.
- **DRY (Don't Repeat Yourself)**: Favor generalized, reusable functions over
  copy-paste-and-tweak. Before adding a new function that closely resembles an
  existing one, refactor the common logic into a shared helper or parameterize
  the existing function to handle both cases. Verify the refactoring preserves
  all prior call sites — tests should pass without changes.
- **Zero-indirection wrappers**: Never create a function that is a pure
  pass-through to another function with the same signature. If inlining the
  call removes no clarity, do it. Trampoline wrappers (`sub foo { bar($_[0]) }`)
  add churn without value.
- **Plan file cleanup**: When implementation of a plan doc is complete and committed, delete the plan file. Plan docs are written in separate sessions and have no ongoing value once the work is done — only commit messages and code remain.
- **Dead code elimination**: Remove unreachable code on sight — orphaned
  subroutines, unregistered routes, unused JavaScript functions, stale
  templates, and commented-out blocks. Dead code includes tests that only
  exist to test dead code; if the code is removed, its tests go with it.
  Before each commit, run `git diff --stat` and review whether every changed
  file still has anything referencing the old pattern. If you are uncertain
  whether something is reachable, search the entire codebase (Perl, JS,
  templates, tests, config) for the identifier before deciding.

  To suppress a false positive, annotate the line with `# DEAD-SUPPRESS: <reason>`.
  The `bin/find_dead_code` tool skips any line preceded by this marker.
- **Self-describing buttons**: Every interactive action button in a fragment
  template must carry `data-action-url` (the POST endpoint) and `data-method`
  attributes so the walkthrough can discover available actions by parsing HTML
  rather than hardcoding endpoint paths. Additional `data-*` attributes (e.g.
  `data-id` for shed items, `data-skill` for skills) are sent as JSON body
  parameters. The walkthrough uses Mojo::DOM to discover buttons and follow
  them — never hardcode an action URL that a button already describes.
- **Test mode** (`MOJO_MODE=test`): When running in test mode the app
  automatically enables all feature flags (`market_counter_offers`,
  `market_multi_item`), disables the rate limiter, and skips the maintenance
  timer. This allows deterministic walkthrough runs without interference.
  Set `MM_RAND_SEED` for reproducible random sequences (artifact draws,
  customer generation, etc.).
- **Health endpoint**: `GET /health` returns `{"ok":1}` with no auth, no
  database reads. The walkthrough uses this for server readiness polling rather
  than relying on a game page fetch.
- **End-to-end walkthrough automation**: Every feature addition or endpoint
  change must include or update `bin/walkthrough` — a Perl script using
  Mojo::UserAgent and Mojo::DOM that launches the app on a background port
  (set `MM_TEST_PORT` or default 9900), waits for `/health` to respond,
  then drives the full game loop:
  - Login → CSRF extraction
  - Game page load
  - Nav discovery (reads `/nav` JSON for current view, tabs, fragment URLs)
  - Fragment fetch (reads HTML buttons with `data-action-url` → follows them)
  - Prospecting (begin → push × 2 → stop)
  - Shed verification
  - Market visit (begin → offer → send_away)
  - Skill purchase
  - Logout
   The walkthrough asserts HTTP status codes (200/204/302), kills the server,
   and exits non-zero on any failure so it gates pre-commit checks. It must be
   updated when new fragment actions or nav states are added.

### Boundary Layers

The application enforces strict boundaries between three layers. No layer leaks
game logic or policy into another.

**Perl backend** — owns all decisions, all game logic, all URLs, all state.
Builds data structures (`actions`, `attrs`, tabs, `_self.actions`, etc.) and
passes them to templates or serializes them as JSON. This is the only layer
where game rules exist.

- Controllers never hardcode a string in JS or wait for a template renderer.
- The action entry format wraps all HTML attributes in an `attrs` hash. Keys are
  exact HTML attribute names; values are attribute values. A value of `undef`
  renders as a boolean attribute (key only, no `="..."`). Example:

  ```perl
  { label => 'Push',
    attrs => { 'data-action-url' => '/prospecting/push',
               'data-method'     => 'POST',
               id                => 'btn-push',
               class             => 'mm-btn mm-btn-primary' } }
  ```

**Templates** — pure iterators. Receive a data structure, walk it, render it.
Never hardcode a URL, never decide what to show based on game state, never
contain conditional logic that encodes game policy.

- `components/action_buttons.html.ep` iterates `$a->{attrs}` keys blindly. It
  knows nothing about `data-action-url`, `data-method`, or any other attribute
  name — it writes the key as the attribute name and the value through `<%= %>`
  for safe HTML escaping.
- Fragment templates pass an `actions` arrayref to the component. They do not
  construct raw `<button>` HTML with hardcoded URLs.
- The nav template iterates whatever tab entries the backend sends. It does not
  know which tab is active, what views exist, or what any fragment URL means.

**JavaScript** — declarative pipeline. Fetch JSON from backend (`/game`,
`/nav`), set `innerHTML` from fragment responses, delegate clicks via
`data-*` attributes. Never compute a URL, never construct HTML, never know
what action a button performs.

- `handleAction` reads `btn.dataset.actionUrl` and `btn.dataset.method`
  blindly. It never references `/prospecting/push` or any other endpoint.
- `renderNavBar` iterates whatever tabs the nav response provides. It never
  knows which tabs exist or what views they map to.
- `applyNav` fetches `/nav`, reads `primary_fragment_url`, fetches that URL,
  and sets `innerHTML`. It never computes a URL, never inspects game state.

**data- attribute to POST body convention**: Every `data-*` attribute on an
action button (except `data-action-url`, `data-method`, `data-confirm`,
`data-redirect`) is sent as a JSON body parameter. The attribute name is
the parameter key:

  - `data-shed-item-id="abc"` → `body.shed_item_id = "abc"`
  - `data-skill="prospecting"` → `body.skill_id = "prospecting"`  *(wait, no — see below)*

The JS conversion: `btn.dataset` provides camelCase keys (`shedItemId`),
which `handleAction` converts to snake_case via
`key.replace(/([A-Z])/g, '_$1').toLowerCase()`.

  - `data-shed-item-id` → `dataset.shedItemId` → `body.shed_item_id`
  - `data-skill` → `dataset.skill` → `body.skill` *(no camelCase, no change)*

**Rule**: The `data-` attribute name MUST match the server-side parameter name
after camelCase-to-snake_case conversion. Use `data-shed-item-id` (not
`data-id`) when the server expects `shed_item_id`. The walkthrough must use
the same conversion when building POST bodies from button attributes.

**Violation example** (do not replicate): A template that hardcodes
`data-action-url="/skills/purchase"` or checks `if ($shed_count > 0)` to
decide rendering. That logic and URL belongs in the Perl backend where it
can be tested.

---

## Design Vault

The `docs/` directory is the canonical design reference. When in doubt
about *how the game should work*, consult the design docs for vision,
philosophy, mechanics, and writing guidance, along with
`GAME_ARCHITECTURE.md` — target rebuild specification.

---

## Source of Truth

| Concern | Authority |
|---------|-----------|
| What the game should do | `docs/` + `GAME_ARCHITECTURE.md` |
| New codebase structure | This directory (`lib/`, `t/`, `templates/`) |
