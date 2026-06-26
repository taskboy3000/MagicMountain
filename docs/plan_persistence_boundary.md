# Persistence Boundary Cleanup

## Goal

Eliminate all direct JSON file I/O outside the Model layer so that swapping
to an SQL-backed ORM requires changes only in `lib/MagicMountain/Model/` (and
its subclasses). Code in commands, controllers, services, and tests must
never construct JSON file paths, call `write_file` on `.json` files, or
`open`/`decode_json` on `.jsonl` files.

## Current Violations

### Tier 1 — Critical (commands that break on SQL swap)

| File | Lines | Problem |
|------|-------|---------|
| `Command/init.pm` | 39–65 | `write_file($path, '{}')` for 6 JSON files |
| `Command/simulate.pm` | 74–79 | Same pattern — 6 JSON files |
| `MagicMountain.pm` | 467 | `-e "$dataDir/seasons.json"` filesystem probe |

### Tier 2 — Transcript/Audit bypasses (commands)

| File | Lines | Problem |
|------|-------|---------|
| `Command/activity.pm` | 24–30 | `open` + `decode_json` on `transcript.jsonl` |
| `Command/report.pm` | 16–23 | Same bypass |

### Tier 3 — Test scaffolding (test-only, low risk)

| File | Lines | Problem |
|------|-------|---------|
| `t/session.t` | 16–21 | Reads `audit.jsonl` via `open`+`decode_json` |
| `t/login.t` | 15–20 | Same audit log read |
| `t/bot_simulate.t` | 16 | `write_file("$data_dir/transcript.jsonl", '')` |
| `t/transcript.t` | 13 | `write_file($file, '')` (unit test of Transcript itself — acceptable) |
| `t/model.t`, all `t/model_*.t` | various | `write_file($tmpfile, '{}')` (unit tests of Model — acceptable) |

### Tier 4 — Bin scripts (standalone, not engine)

Not addressed here — they're analysis tools that read pre-existing files,
not part of the game engine.

---

## Fix Plan

### Step 1 — `MagicMountain.pm:ensureActiveSeason`

Replace `-e` filesystem check with a Model-level check:

```perl
# Before:
my $seasons_file = $self->dataDir . '/seasons.json';
if (!-e $seasons_file) { ... }

# After:
$self->seasons->load;
if (!scalar keys %{ $self->seasons->all }) { ... }
```

Test: existing season-related tests exercise this path indirectly.

### Step 2 — `Command/init.pm`

Replace `write_file` per-file with Model API. The file-to-model mapping:

| JSON file | Model class |
|-----------|-------------|
| `accounts.json` | `Model::Account` |
| `characters.json` | `Model::Character` |
| `sessions.json` | `Model::Session` |
| `seasons.json` | `Model::Season` |
| `shed.json` | `Model::ShedItem` |
| `activities.json` | `Activity::Prospecting` (uses `Model`) |
| `dispositions.json` | `Model::ArtifactDisposition` |
| `faction_snapshots.json` | `Model::FactionSnapshot` |
| `season_records.json` | `Model::SeasonRecord` |

For each, replace `write_file($path, '{}')` with
`ModelClass->new(file => $path)->save`. The `save` method creates the JSON
file with `{}` table structure automatically when `row` has no `id`.

For `audit.jsonl` and `transcript.jsonl`, replace `write_file($path, '')`
with `unlink $path` (they are append-only and recreate on first write).

### Step 3 — `Command/simulate.pm`

Same fix as Step 2 — replace direct `write_file` with `Model->new(...)->save`
for all 9 JSON files. Replace `write_file("$data_dir/transcript.jsonl", '')`
with `unlink` (same reasoning — Transcript creates the file on first append).

Also replace `File::Copy::copy($transcript_file, $output)` (line 233) with a
`Transcript->export($path)` method to avoid direct filesystem `copy()` calls.

### Step 4 — `Command/activity.pm` and `Command/report.pm`

Add `all_events` to `Model::Transcript` — returns an arrayref of decoded
event hashes by reading all lines from the JSONL file.

`Command/activity.pm` always uses the app's default transcript path, so
replace inline `open`+`decode_json` with `$self->app->transcript->all_events`.

`Command/report.pm` accepts a `--transcript` custom path. When provided,
instantiate `MagicMountain::Model::Transcript->new(file => $custom_path)`
and call `all_events` on it. Otherwise use `$self->app->transcript`.

### Step 5 — `t/session.t` and `t/login.t`

Replace inline `open`+`decode_json` with `Model::AuditLog` methods. Add
a `all_entries` method to `Model::AuditLog` if one doesn't exist.

### Step 6 — `t/bot_simulate.t`

Replace `write_file("$data_dir/transcript.jsonl", '')` with
`$t->app->transcript->clear` or instantiate the model and save an empty
state.

### Step 7 — Verify

1. `prove -l t/` — all tests pass
2. `perl -Ilib script/mountain init` — creates valid empty data directory
3. `perl -Ilib script/mountain simulate` — runs simulation successfully
4. `perl bin/walkthrough` — end-to-end game loop

---

## What stays (intentionally)

| File | Reason |
|------|--------|
| `t/model.t`, `t/model_*.t` `write_file` calls | Unit-testing the Model layer itself. These will change when the Model's backend changes. |
| `bin/analyze`, `bin/run_many`, `bin/check_loyalist_balance` | Standalone analysis scripts, not part of the game engine. |
| Controllers + Services | Already clean — verified by audit. |
