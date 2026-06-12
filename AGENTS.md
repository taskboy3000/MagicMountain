# Magic Mountain — AGENTS.md

> Reimplementation of Magic Mountain on a clean foundation.

---

## What Is This?

**Magic Mountain** is a multiplayer, seasonal push-your-luck web game. Players
extract strange artifacts from a mysterious mountain, destabilize ("push") them
for greater value (risking catastrophic collapse), and sell to competing
factions. Each ~30 day season is a tournament: highest cumulative score wins.

**Core loop**: Prospect → Push (repeat) → Stop → Choose buyer → Repeat until
out of turns → Day rollover → Season ends.

The original working implementation lives in `original/`. This repo is a
ground-up reimplementation following the architecture spec in
`GAME_ARCHITECTURE.md`.

---

## Directory Layout

```
magic_mountain/
├── AGENTS.md                      # This file — project guide for AI agents
├── GAME_ARCHITECTURE.md           # Target architecture spec (authoritative)
├── Makefile                       # test, cover, indent targets
├── cpanfile                       # Perl dependencies (Mojolicious, YAML::XS, etc.)
├── magic_mountain.yml             # App config (secrets, session_timeout_minutes)
│
├── lib/                           # NEW CODEBASE (under construction)
│   ├── MagicMountain.pm           # Mojolicious app: routes, helpers, attributes
│   └── MagicMountain/
│       ├── Controller.pm            # Base controller (empty, inherits Mojolicious::Controller)
│       ├── Controller/Root.pm       # Gateway redirect (GET / → /login or /game)
│       ├── Controller/Sessions.pm   # Login form, login, logout, session management
│       ├── Controller/Player.pm     # Current player info (GET /player)
│       ├── Controller/Game.pm       # Game state page (GET /game)
│       ├── Model.pm                 # Base persistence class (JSON file CRUD, UUID, find)
│   ├── Model/Account.pm         # Player accounts (username, password)
│   ├── Model/AuditLog.pm        # JSONL event log (login, logout, account creation)
│   ├── Model/Character.pm       # Per-season character (name, score, account_id)
│   ├── Model/Season.pm          # Season config (length, day, end_of_day_hour)
│   ├── Model/HallOfFame.pm      # Hall of Fame entries
│   ├── Model/Session.pm         # Server-side session tracking (player_id, last_active)
│   └── Command/
│       ├── create_account.pm    # CLI: create-account --name <username>
│       ├── delete_account.pm    # CLI: delete-account --name <username>
│       ├── disable_account.pm   # CLI: disable-account --name <username>
│       └── list_accounts.pm     # CLI: list-accounts (with online/offline status)
│
├── templates/
│   ├── layouts/default.html.ep    # Bootstrap 5 layout wrapper
│   ├── sessions/new.html.ep       # Login form with vanilla JS fetch
│   └── game/show.html.ep          # Authenticated home page with season info
│
├── public/css/                    # Frontend assets (currently empty)
├── public/js/
│
├── t/                             # Test suite
│   ├── model.t                    # Base Model class tests
│   ├── model_account.t            # Account model tests
│   ├── model_character.t          # Character model tests
│   ├── model_season.t             # Season model tests
│   ├── model_hall_of_fame.t       # Hall of Fame model tests
│   ├── login.t                    # Login flow integration tests
│   └── session.t                  # Session lifecycle tests (create, touch, expire, logout)
│
├── original/                      # PREVIOUS WORKING CODEBASE (reference)
│   ├── AGENTS.md                  # Migration plan and authority table
│   ├── ARCHITECTURE.md            # Target architecture for migration
│   ├── lib/MagicMountain/         # Full game: Engine, Activities, Factions, Market, Bot
│   ├── t/                         # Comprehensive test suite (~100+ tests)
│   └── content/                   # YAML artifact definitions
│
├── design_docs/                   # Obsidian design vault
│   ├── Core Design.md             # Game vision, premise, philosophy
│   ├── Artifact Mechanics.md      # Push/collapse/breakthrough math
│   ├── Engine Design.md           # Time structure, core loop, systems
│   ├── Tone Guide.md              # Narrative voice and writing rules
│   ├── MVP 1.0.md                 # Original implementation plan
│   └── ...                        # Factions, Events, PvP, etc.
│
└── script/mountain                # App entry point: perl script/mountain <command>
```

---

## Current Status: Early Rebuild

The new codebase has the persistence layer, authentication, and session
management. Game logic (Engine, Prospecting, Market, Factions, Bot) has not
been ported yet. The `original/` directory contains the full reference
implementation.

| Layer | Status | Files |
|-------|--------|-------|
| App shell | Done | `MagicMountain.pm`, `Controller.pm`, `Controller/Root.pm` |
| Persistence | Done | `Model.pm` + Account, AuditLog, Character, Season, HallOfFame, Session |
| Auth/Sessions | Done | `Controller/Sessions.pm`, `Controller/Player.pm`, `Model/Session.pm` |
| CLI commands | Done | `create_account.pm`, `delete_account.pm`, `disable_account.pm`, `list_accounts.pm` |
| Web UI | Done | Login form, game page with season info, player JSON endpoint |
| Game engine | TODO | (in `original/`) |
| Activities | TODO | (in `original/`) |
| Market/Factions | TODO | (in `original/`) |

### Infrastructure Backlog

Deferred until later in development:

| Concern | Priority | Notes |
|---------|----------|-------|
| Password/email auth | Medium | Current name-only auth is fine for alpha. Email verification flow planned post-MVP. |
| CSRF protection | Medium | Mojo has `csrf_protect` plugin. Needed before accepting writes from real users. |
| Rate limiting | Medium | Brute-force prevention on login. Mojo `under` hooks can count attempts. |
| HTTPS enforcement | Low | Required for production. Handled at reverse proxy (nginx) or via Mojo config. |
| Filesystem persistence | Low | JSON files work for single-server dev. MariaDB migration planned (GAME_ARCHITECTURE.md §18.2). |

---

## Running the App

```bash
# Start dev server
perl -Ilib script/mountain daemon

# CLI commands
perl -Ilib script/mountain create-account --name alice
perl -Ilib script/mountain list-accounts
```

## Testing

```bash
# Run all tests
prove -l t/

# Run specific test
prove -lv t/session.t
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Web framework | Mojolicious 9.40+ (Perl) |
| Persistence | JSON files with atomic write-via-temp-file + flock |
| Config | YAML (`magic_mountain.yml`) |
| Frontend | Bootstrap 5.3 CDN, vanilla JS |
| Testing | Test::More, Test::Mojo |
| Perl | 5.28+ with signatures (`-signatures`) |

---

## Key Conventions

- **Models**: Subclass `MagicMountain::Model`. Declare `columns`, use
  `getCol`/`setCol` accessors. Persist with `save()`, load with `load()`,
  query with `find()`.
- **Controllers**: Subclass `MagicMountain::Controller`. Return JSON for API
  endpoints. Use `$self->session(playerId => ...)` for auth.
- **Commands**: Subclass `Mojolicious::Command`. Register namespace in
  `MagicMountain.pm`.
- **Config**: Add defaults in `MagicMountain.pm` → `defaultConfig`. Override
  in `magic_mountain.yml`.
- **Tests**: Use `Test::Mojo` for integration. Use `tempdir(CLEANUP => 1)`
  with `$ENV{MM_DATA_DIR}` for isolated state. Pre-populate JSON files as needed.

---

## Design Vault

The `design_docs/` directory is the canonical design reference. When in doubt
about *how the game should work*, consult:
1. `design_docs/Core Design.md` — game vision and philosophy
2. `design_docs/Artifact Mechanics.md` — core math
3. `design_docs/Engine Design.md` — systems and architecture
4. `design_docs/Tone Guide.md` — writing style
5. `GAME_ARCHITECTURE.md` — target rebuild specification

---

## Source of Truth

| Concern | Authority |
|---------|-----------|
| What the game should do | `design_docs/` + `GAME_ARCHITECTURE.md` |
| New codebase structure | This directory (`lib/`, `t/`, `templates/`) |
| Reference implementation | `original/lib/MagicMountain/` |
| Architectural invariants | `original/.opencode/rules/` |
