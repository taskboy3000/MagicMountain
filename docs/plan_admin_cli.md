# Plan: Expand Administrative CLI

## Context
- Stack: Perl (Mojolicious/Moo/Durance-like Model), Mojolicious::Commands
- Existing CLI: 13 custom commands under `MagicMountain::Command` namespace,
  registered via `push @{ $self->commands->namespaces }, 'MagicMountain::Command'`
  in `MagicMountain.pm:373`. Each is a `.pm` file in `lib/MagicMountain/Command/`.
- Auth model: CLI runs in-process (no admin secret needed). Only the HTTP admin
  bridge (`/admin/*`) uses `X-Admin-Secret`.
- Pattern: Each command subclasses `Mojolicious::Command`, declares `has description`
  and `has usage`, implements `sub run ($self, @args)`.
- Tests: `Test::Mojo` integration tests in `t/`. Tests verify state via model reload
  + `getCol`, not stdout capture. Each command needs a smoke test and a data-path test.
- Coverage: `make cover && make report` before commit. Each new module needs coverage.
- Tooling: `make indent && make clean && make ci-check`
- Output convention: `printf/say` with column headers + separator line for tabular
  output (see `list_accounts.pm`).

## Existing commands (baseline)
activity, advance-day, create-account, create-season, delete-account,
disable-account, end-season, init, list-accounts, migrate-tokens,
report, reset-token, simulate

## Design decisions per reviewer findings

### Combined / deduplicated commands
- **show-account** is account-only (id, username, banned flag, session active).
  Character data removed from this command.
- **show-character --name <username>** is the full character dump (all columns,
  shed count, faction sales, standing, pending_activity, result). This is the
  single character-inspection command.
- **set-scrap** replaces both `set-scrap` and `add-scrap`. Use `--value N` for
  absolute, `--add N` for increment. One command, two modes.
- Character mutation commands share a `_find_character($name)` helper via a
  common base class `MagicMountain::Command::CharacterMutator`.

### Deferred (lower value for an operator running their own server)
- ~~`show-factions`~~ — subsumed by `show-season` (faction_state included).
- ~~`show-config`~~ — useful for tuning but not ops-critical. Move to a future
  "tuning tools" batch.
- ~~`audit-log`~~ — nice to have but the JSONL file is trivially greppable.
- ~~`shed-stats`~~ — non-trivial aggregator. Low urgency for server ops.
- ~~`bot-run-day`~~ — debugging tool for bot profile authors; niche.
- ~~`maintenance-status`~~ — `advance-day` already covers the trigger use case;
  status info folded into `show-season`.

### Invariant handling for character mutation
- `set-score` accepts `--force` to bypass the non-decreasing-score invariant.
  Without `--force`, it enforces score >= current (same as gameplay).
- All other mutation commands (`set-scrap`, `set-ap`, `set-skill`) call
  `setCol` + `save` which triggers `Model::Character->validate()` for
  standard invariant enforcement. No `--force` needed (these invariants
  are clamping/range checks, not monotonicity).

### Architectural notes
- `archive-season --finalize` calls `Model::Season->finalize()` which is
  known architectural debt (game logic in a Model class). The existing
  `end-season` command does the same. Not fixing here, but document the
  preferred `SeasonManager` path for future refactoring.
- Step 10 character mutation uses `_find_character` helper in a shared base
  class to avoid 5x copy-paste.
- All list commands use the `list_accounts.pm` table format: column headers,
  separator line, `sprintf` with widths.
- No HTTP admin endpoint changes needed. CLI-only expansion.

---

## Steps (ordered by safety + value)

### Step 1: `enable-account` — unban from CLI
**Goal**: Mirror HTTP admin `POST /admin/account/unban` as CLI command.
  Completes the ban/unban pair started by `disable-account`.
**Implementation**: `lib/MagicMountain/Command/enable_account.pm`.
  `--name <username>`. Calls `setCol('banned', 0); $account->save`.
  Logs `account_enabled` via `$self->app->audit_log->log(...)` mirroring
  `disable_account.pm` audit pattern. Does NOT manage sessions (unbanning
  does not restore closed sessions).
**Tests**: Create banned account, run enable-account, verify `banned == 0`
  via `getCol`. Verify audit log entry exists.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 2: `show-season` — active season details
**Goal**: Show current season: label, day, length, status, faction state
  summary (per-faction influence, artifacts_received, daily_intake,
  days_since_purchase), faction_climate, crier message, global_event_text,
  daily_modifiers.
**Implementation**: `lib/MagicMountain/Command/show_season.pm`.
  `--id <uuid>` or defaults to active season. `die "No active season.\n"`
  if none found (matching `list_accounts.pm` pattern).
  Prints key columns + formatted faction_state table + climate + crier text.
  Output uses structured key:value lines, not tabular.
**Tests**: With active season, run command, verify label/day/length/status
  match. Empty faction_state yields graceful "no faction data" message.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 3: `show-character` — single character dump
**Goal**: Full character dump: all columns, shed item count, faction sales,
  standing, pending_activity, result card. This is THE single character
  inspection command (see Step 2 for account-only view).
**Implementation**: `lib/MagicMountain/Command/show_character.pm`.
  `--name <username>`. Resolves account via `accounts->find_by_username`,
  then character in active season via `characters->find(sub { ... })`.
  `die "No character found for account '$name'.\n"` if no character exists.
  Prints structured key:value output.
**Tests**: Create character with shed items + faction sales, run show-character,
  verify all output fields present via `getCol` reload.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 4: `list-seasons` — all seasons table
**Goal**: List all seasons with id, label, status, day/length, last_maintenance.
**Implementation**: `lib/MagicMountain/Command/list_seasons.pm`.
  Iterates `$app->seasons->all`, shows `sprintf` table sorted by label,
  using `list_accounts.pm` column-header + separator convention.
  Empty state prints "No seasons found." instead of table.
**Tests**: Create 2 seasons with different statuses (active + archived),
  run list-seasons, verify both appear with correct status.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 5: `list-characters` — characters in a season
**Goal**: Show all characters with name, score, scrap, AP, is_bot, skills.
**Implementation**: `lib/MagicMountain/Command/list_characters.pm`.
  `--season active` (default) or `--season-id UUID`.
  `die "No active season.\n"` if default used and none exists.
  `--bot` / `--human` filter. `--sort score` (default).
  Table format matching `list_accounts.pm`.
**Tests**: Create 2 characters (one bot, one human), run list-characters,
  verify both appear. Test `--bot` filter shows only bot.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 6: `set-season-day` — override season day counter
**Goal**: Manually set season day (testing / recovery).
**Implementation**: `lib/MagicMountain/Command/set_season_day.pm`.
  `--day N` (required, >= 1). Finds active season or `--id <uuid>`.
  Does NOT clamp at season length but warns via say to stderr:
  "Warning: day (N) exceeds season length (L)".
  Calls `$season->setCol('day', $n); $season->save`.
**Tests**: Set day to 15, reload via `getCol('day')`, verify.
  Set beyond length, verify warning message.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 7: `archive-season` — archive without finalizing
**Goal**: Move season to 'archived' status without running full finalization.
**Implementation**: `lib/MagicMountain/Command/archive_season.pm`.
  `--id <uuid>` or `--label <label>`. Sets status => 'archived', saves.
  `--finalize` also runs `Season->finalize($app)` which acts on active
  season regardless of `--id` (known behavior — documented limitation).
  Without `--finalize`, characters/pending items survive (orphaned).
  Warn about orphaned data if archiving active season without `--finalize`.
**Tests**: Archive active season without `--finalize`, verify status changed,
  characters still in data. Test `--finalize` removes characters.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 8: `set-scrap` — adjust character scrap
**Goal**: Set or add to a character's scrap.
**Implementation**: `lib/MagicMountain/Command/set_scrap.pm`
  (extends `CharacterMutator` base class).
  `--name <username>`. Either `--value N` (absolute, scrap >= 0) or
  `--add N` (increment, may be negative but result must be >= 0).
  Uses `setCol('scrap', $n)`, triggers `Model::Character->validate()`.
**Tests**: Set scrap to 50, verify. Add to scrap, verify sum. Try negative
  scrap, verify die/error.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 9: `set-score` — adjust character score
**Goal**: Set a character's score (admin recovery). Score is normally
  monotonic — this can bypass that.
**Implementation**: `lib/MagicMountain/Command/set_score.pm`
  (extends `CharacterMutator` base class).
  `--name <username> --value N`. Without `--force`, enforces score >= current
  (same as gameplay invariant). With `--force`, directly sets `setCol('score', $n)`
  bypassing the monotonicity check. Both paths clamp at >= 0.
  The `--force` flag is documented as "only for recovery — use with care."
**Tests**: Set score higher, verify. Set score lower without `--force`, verify
  error. Set score lower with `--force`, verify value accepted.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 10: `set-ap` — adjust action points
**Goal**: Set a character's current action points (recovery/testing).
**Implementation**: `lib/MagicMountain/Command/set_ap.pm`
  (extends `CharacterMutator` base class).
  `--name <username> --value N`. 0 <= N <= action_points_max.
  Calls `setCol('action_points', $n)`, triggers validate().
**Tests**: Set AP to 5, verify. Try negative, verify die. Try above max,
  verify die.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 11: `set-skill` — adjust skill level
**Goal**: Set a character's skill level (recovery/testing).
**Implementation**: `lib/MagicMountain/Command/set_skill.pm`
  (extends `CharacterMutator` base class).
  `--name <username> --skill <name> --level N`.
  Skill name is one of: prospecting, upcycling, selling. Level 0-4.
  `die "Unknown skill: $skill\n"` on invalid. Calls `setCol(skill_$skill, $n)`.
**Tests**: Set prospecting to 2, verify. Try level 5, verify die.
**Verify**: `prove t`, `make indent`, `make cover`

### Step 12: CharacterMutator base class
**Goal**: Shared character-lookup helper for Steps 8-11.
**Implementation**: `lib/MagicMountain/Command/CharacterMutator.pm`.
  Provides `_find_character($name)` that resolves account -> active season
  character, or dies with clear message. Subclasses call:
  ```perl
  my $char = $self->_find_character($name);
  ```
  This eliminates 4x copy-paste of the account-then-character lookup.
**Tests**: Tested implicitly via Steps 8-11 (each exercises the helper).
  Unit test for the helper itself if feasible.
**Verify**: `prove t`, `make indent`, `make cover`

---

## Changelog vs original draft

| Change | Reason | Source |
|--------|--------|--------|
| Removed `show-config`, `show-factions`, `audit-log`, `shed-stats`, `bot-run-day`, `maintenance-status` | Deferred per MVP cut analysis | impl-reviewer |
| Merged `show-account` + `show-character` overlap | `show-account` dropped; `show-character` is THE inspection command | arch-reviewer, impl-reviewer |
| Merged `set-scrap` + `add-scrap` into one `set-scrap` with `--value`/`--add` | Combine similar commands | impl-reviewer |
| Added `CharacterMutator` base class for steps 8-11 | Eliminates 4x copy-paste | impl-reviewer |
| Step 1: added audit logging + session cleanup note | Missing from original plan | arch-reviewer |
| Step 7: documented `--finalize` ignores `--id` | Season->finalize class method limitation | impl-reviewer |
| Step 9: added `--force` for score decrease | Invariant bypass strategy | arch-reviewer, impl-reviewer |
| Step 16 removed (maintenance-status) | `advance-day` already covers trigger; status folded into `show-season` | impl-reviewer |
| Step 14 removed (shed-stats) | Non-trivial aggregation, low urgency | impl-reviewer |
| Removed "Reads audit.jsonl" language | Must use model API, not raw file I/O | arch-reviewer |
| Coverage check in every Verify step | Was missing from original | impl-reviewer |
| Test verification method specified | Was underspecified | impl-reviewer |
| Output format convention specified | Was underspecified | impl-reviewer |
