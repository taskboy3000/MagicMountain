# ProspectBoy 3000 — AGENTS.md

Multiplayer push-your-luck web game. Prospect artifacts → push for value →
sell to factions. Seasonal (~30 day) tournaments. See `GAME_ARCHITECTURE.md`.

---

## Quick Reference

```bash
bash start.sh                  # dev server on :9000
perl bin/walkthrough           # end-to-end loop
make ci-check                  # tests + walkthrough + perlcritic
make cover && make report      # coverage (85%+ required)
perl -Ilib script/mountain advance-day   # manual day rollover
```

---

## Architecture Rules

**Perl backend owns all decisions, game logic, URLs, state.** Templates iterate
data structures blindly. JS fetches JSON, sets innerHTML, delegates clicks via
`data-*`. Never hardcode a URL or game rule outside the backend.

**Controllers MUST NOT** implement game rules, calculate derived state, build
recs, assemble narrative, determine navigation policy, or mutate domain objects
except through model/service APIs. They extract HTTP params, dispatch to
services/activities, stash, render.

**Services** for extracted logic live in `lib/MagicMountain/Service/`.

**Activities** subclass `MagicMountain::Activity`. Declare `transitions`,
implement one handler per action. Dispatch via `$activity->dispatch($char, $action)`.
Handlers own all persistence (saves, deletes, FK management). Transcript writes
use inherited `_log_event($char, \%data)` — never `$self->app->transcript`.

**Models** subclass `MagicMountain::Model`. Declare `columns`, use
`getCol`/`setCol` accessors. Never access `$self->{row}` directly outside the
model class.

**All URLs through url_for**: Controllers AND templates MUST generate every
URL via `url_for('named_route')` — never hardcode a path string like
`'/market/send_away'`. This is what makes reverse-proxy sub-path deployment
work: the `url_for` override in `Controller.pm` prepends the proxy prefix
to every generated URL. Hardcoded paths bypass the override and break behind
the proxy.

**Controllers compute URLs, templates render them**: Controllers call
`$self->url_for('route_name')` and stash the result. Services receive URLs
as pre-computed strings passed from the controller — NEVER call url_for
inside a service. This keeps URL construction in the controller layer where
it belongs.

**data-attribute to POST body**: camelCase dataset key → snake_case param name.
`data-shed-item-id="abc"` → `body.shed_item_id = "abc"`.

---

## Conventions

- **CI check**: `make ci-check` before every `git push` — catches test failures,
  walkthrough regressions, and perlcritic violations before they reach CI.
  `make verify` is the faster post-implementation gate (structural checks only).
- **Formatting**: `make indent && make clean` before commit.
- **Coverage**: `make cover && make report` before commit (85%+).
- **Tests**: `Test::Mojo` integration. Use Model objects (`->create`, `->save`)
  to set up state in tempdirs — never `write_file` to `*.json`.
- **Walkthrough**: Every endpoint change updates `bin/walkthrough`.
- **TUNING.md**: Update `docs/TUNING.md` when changing defaults or content YAML.
- **State files before writing**: For non-trivial changes, name the affected files
  and call path before code. Human reviews for layer violations.
- **Post-verify**: Run `make verify` after every implementation session.
  For full proof, trigger the `@post-verify` agent which reads the diff,
  runs simulations, and produces a pass/fail report.
- **Commit discipline**: Never commit without review. Group related changes.
  Message: reason first, then summary of changes.
- **Plan files**: `docs/plan_$NAME.md`. Delete after implementation. Never commit.
- **Completion checklist**: Route exercised, stash vars verified, new methods
  tested, no State internals accessed, transcript through `_log_event`,
  tests pass reported.

---

## Model Usage (MagicMountain::Model)

### Key Patterns

| Operation | Code |
|-----------|------|
| Create | `my $r = $model->create(col => $val); $r->save;` |
| Read one | `my $r = $model->get($uuid)` — returns new object sharing C<table> |
| Read many | `my @rows = @{ $model->find(sub { $_[0]->{col} eq $val }) }` |
| Update | `$r->setCol('col', $newval); $r->save;` |
| Delete | `$model->delete($uuid)` |

### Critical: `get()` Returns a Row Copy

`$model->get($id)` returns a new object whose C<row> is a **shallow copy**.
C<setCol> writes to the copy, not to the shared table. C<save> copies the row
back to the table AND writes the full file. This means:

  - **Single-record update**: use `setCol` + `save` as normal.
  - **Batch update**: use `setCol` + `sync_row` per item, then one `save_table`.

### Batch Update Pattern (avoids N full-table writes)

```perl
my $model = $self->app->some_model;
$model->load;
for my $id (keys %{ $model->table }) {
    my $item = $model->get($id) or next;
    $item->setCol('field', $new_value);
    $item->sync_row;        # copy row back to table (no write)
}
$model->save_table;          # one write for all changes
```

### Banned

  - `$model->table->{$id}` — bypasses column validation. Use `get` + `setCol`.
  - `$model->_saveTable` — private. Use `$model->save_table`.

---

## Source of Truth

| Concern | Authority |
|---------|-----------|
| Game design | `docs/` + `GAME_ARCHITECTURE.md` |
| Codebase structure | `GAME_ARCHITECTURE.md` (directory layout) |
| Module boundary rules | `.opencode/rules/` — loaded automatically per-file |
| Conventions & standards | This file |
