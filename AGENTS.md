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

## Design Principles


0. Every feature should be implementable without Mojolicious. The web controllers are adapters that expose engine functionality over HTTP; they are not part of the game engine itself. The wen UI is one client of the REST API. There will be others in the future.
1. **Prefer data over branching.** When choosing between a data structure
   (tables, hashes, YAML, registries, dispatch maps) and if/elsif chains,
   prefer the data-driven design.
2. **Every layer has one responsibility.** Business logic belongs in the domain
   model; templates render data; JavaScript orchestrates UI events; persistence
   stores state.
3. **Represent decisions as data, not code.** Dispatch tables, transition
   tables, and configuration are preferred over hard-coded control flow because
   they are easier to inspect, test, and extend.
4. **Design for deterministic verification.** Favor architectures validated by
   tests, static analysis, simulations, coverage, and other automated tooling.
5. **Eliminate duplication by improving the model.** If a feature requires
   repeated branching or special cases, first ask whether the underlying data
   model is missing an abstraction.

---

## Controller Boundaries

Controllers are HTTP adapters only. They must not become another business layer.

**Controllers MUST NOT:**
- implement game rules
- calculate derived game state
- build recommendation engines
- assemble narrative or recap content
- determine navigation policy (tab enable/disable, view resolution)
- mutate domain objects except through model/service APIs

**Controllers SHOULD:**
- extract HTTP parameters and session information
- invoke domain services or Activity dispatch
- stash returned view models or pass them to templates
- render templates or serialize JSON

**Warning sign:** If a controller grows multiple private helper methods that
calculate game state, that logic belongs in a model or service. Extract it.

> Extracted services live in `lib/MagicMountain/Service/`. They receive `$self->app`
> like Activities do (consistent with the existing `ShedManager` pattern).

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Web framework | Mojolicious 9.40+ (Perl) |
| Persistence | JSON files, atomic write-via-temp-file + flock |
| Config | YAML (`magic_mountain.yml`, `content/*.yml`) |
| Frontend | Normalize.css, IBM Plex Mono, custom CSS, vanilla JS |
| Testing | Test::More, Test::Mojo |
| Perl | 5.28+ with signatures (`-signatures`) |

---

## Running & Testing

```bash
perl -Ilib script/mountain daemon                              # dev server
perl -Ilib script/mountain advance-day                         # manual day rollover
bash start.sh                                                  # kill+restart on :9000
prove -l t/                                                    # full test suite
prove -lv t/nav_web.t                                          # single test
perl bin/walkthrough                                           # end-to-end game loop
make cover && make report                                      # coverage (85%+ required)
```

---

## Key Conventions

- **Models**: Subclass `MagicMountain::Model`. Declare `columns`, use
  `getCol`/`setCol` accessors. Persist with `save()`, load with `load()`,
  query with `find()`.
- **Activities**: Subclass `MagicMountain::Activity`. Declare `transitions`,
  implement one handler per action. Dispatch via
  `$activity->dispatch($char, $action)`. Handlers own all persistence
  (saves, deletes, FK management).
- **Controllers**: Return JSON or fragments. Use `$self->session(playerId => ...)`
  for auth. Dumb pipes — call `dispatch`, pipe `view` to template.
- **Commands**: Subclass `Mojolicious::Command`. Register in `MagicMountain.pm`.
- **Tests**: Use `Test::Mojo` for integration. Use `tempdir(CLEANUP => 1)` with
  `$ENV{MM_DATA_DIR}` for isolated state. Never `write_file` directly to `*.json`
  — always use Model objects (`->create`, `->save`) to set up test state.
- **Formatting**: Run `make indent && make clean` before every commit.
- **Coverage**: Run `make cover && make report` before every commit. All
  `lib/*.pm` files must stay at or above **85%** statement coverage.
- **Dead code elimination**: Remove unreachable code on sight. Annotate false
  positives with `# DEAD-SUPPRESS: <reason>`.
- **Self-describing buttons**: Every action button carries `data-action-url`
  and `data-method` so the walkthrough discovers actions by parsing HTML.
- **Walkthrough**: Every feature addition or endpoint change must include or
  update `bin/walkthrough`.
- **Smoke-test**: Run `bash bin/smoke_test_endpoint GET /<resource>?_format=fragment`
  after template/controller changes. Check for 200 (data) or 204 (no data).
- **Health endpoint**: `GET /health` returns `{"ok":1}` — no auth, no DB reads.
- **Test mode** (`MOJO_MODE=test`): Enables all feature flags, disables rate
  limiter and maintenance timer. Set `MM_RAND_SEED` for reproducible sequences.
- **No automatic commits**: Never commit without being asked.
- **DRY**: Favor generalized, reusable functions over copy-paste.
- **Zero-indirection wrappers**: Never create a function that is a pure
  pass-through to another with the same signature.
- **Plan file creation**: Plan files should by named 'docs/plan_$THING_TO_BE_DONE.md'
- **Plan file cleanup**: Delete plan docs after implementation is committed.

---

## Boundary Layers

Three strict layers. No layer leaks game logic or policy into another.

**Perl backend** — owns all decisions, all game logic, all URLs, all state.
Builds data structures (`actions`, `attrs`, tabs, `_self.actions`, etc.) and
passes them to templates or serializes as JSON. This is the only layer where
game rules exist.

The action entry format wraps all HTML attributes in an `attrs` hash. Keys are
exact HTML attribute names; values are attribute values. `undef` renders as a
boolean attribute (key only, no `="..."`):

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

- `components/action_buttons.html.ep` iterates `$a->{attrs}` keys blindly.
- Fragment templates pass an `actions` arrayref to the component.
- The nav template iterates whatever tab entries the backend sends.

**JavaScript** — declarative pipeline. Fetch JSON from backend (`/game`,
`/nav`), set `innerHTML` from fragment responses, delegate clicks via
`data-*` attributes. Never compute a URL, never construct HTML, never know
what action a button performs.

- `handleAction` reads `btn.dataset.actionUrl` and `btn.dataset.method` blindly.
- `renderNavBar` iterates whatever tabs the nav response provides.
- `applyNav` fetches `/nav`, reads `primary_fragment_url`, fetches that URL,
  and sets `innerHTML`.

**data-attribute to POST body convention**: Every `data-*` attribute on an
action button (except `actionUrl`, `method`, `confirm`, `redirect`) is sent
as a JSON body parameter. The JS conversion maps camelCase dataset keys to
snake_case. The attribute name MUST match the server-side parameter name
after conversion:

- `data-shed-item-id="abc"` → `body.shed_item_id = "abc"`
- `data-skill="prospecting"` → `body.skill = "prospecting"`

**Violation example** (do not replicate): A template that hardcodes
`data-action-url="/skills/purchase"` or checks `if ($shed_count > 0)` to
decide rendering. That logic and URL belongs in the Perl backend where it
can be tested.

---

## Source of Truth

| Concern | Authority |
|---------|-----------|
| What the game should do | `docs/` + `GAME_ARCHITECTURE.md` |
| Codebase structure | `GAME_ARCHITECTURE.md` (directory layout) |
| Conventions & standards | This file |
