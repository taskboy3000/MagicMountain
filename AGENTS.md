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

## Testing

```bash
# Run all tests
prove -l t/

# Run specific test
prove -lv t/prospecting_web.t
```

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
- **Balance checks**: Run `make check-coverage` for fast static validation
  that all faction interest tags have adequate artifact coverage. Run
  `make check-loyalist` (~15s) to verify each faction can support a viable
  loyalist strategy via simulation. Run these when modifying
  `content/prospecting.yml` or `content/factions.yml`.

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
