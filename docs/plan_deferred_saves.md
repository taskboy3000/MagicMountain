# Deferred Saves During Bot Processing

## Problem

In `on_maintenance` (`MagicMountain.pm:165`), the bot loop calls
`bot_runner->run_day` for each bot. Inside `run_day`, every `dispatch()` call
triggers `save()` on various models, which writes the **entire JSON table** to
disk. With 16 bots × multiple actions each:

| Model       | Writes | Size               |
|-------------|--------|--------------------|
| Character   | ~55    | 16 records         |
| Prospecting | ~20    | ~140 records       |
| MarketVisit | ~20    | ~140 records       |
| ShedItem    | ~15    | ~380 records       |
| Season      | ~5–7   | 3 records          |

**Root cause:** every `$char->save`, `$activity->save`, etc. calls `_saveTable`
which writes the full JSON. In-memory table state is correct after each save —
the disk writes are redundant within a single synchronous maintenance pass.

A deeper architectural issue compounds this: three Model subclasses
(Prospecting, MarketVisit, BlackMarket) each claim ownership of
`activities.json`, but it is a single discriminator-based table (`type` column).
Each subclass creates its own table hashref, so changes via one are invisible to
the others in-memory.

## Solution

### Part A: Single Authoritative Activities Model

```
MagicMountain::Model::Activity -> Model     (owns load, dirty, save_table, flush)
     ↑ shared table + _saveTable delegation
     |
Activity (base) → has store; _saveTable delegates to store
 ├── Prospecting   (type='prospecting', find/get filter by type)
 ├── MarketVisit   (type='market_visit')
 └── BlackMarket   (type='black_market')
```

#### New: `lib/MagicMountain/Model/Activity.pm`

The single persistence owner for `activities.json`. Inherits all standard Model
behavior (load, save, delete, find, get, create).

```perl
package MagicMountain::Model::Activity;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(char_id type phase artifact customer pending_event) ];
};
1;
```

#### Changed: `lib/MagicMountain/Activity.pm`

- Add `has store => sub { die "store required" }` — reference to the shared
  `MagicMountain::Model::Activity` instance
- Override `_saveTable` to delegate to the store:

```perl
sub _saveTable ($self) {
    return $self->store->_saveTable;
}
```

This is the critical wiring. `Model::save` is inherited unchanged — it updates
the row in the shared table hashref and calls `_saveTable`. The override routes
`_saveTable` to the store, which controls deferred state and disk writes.

- Add `has _activity_type => sub { die "_activity_type is abstract" }` — used
  for type filtering
- Override `get()` and `find()` to filter by `_activity_type`
- Override `create()` to propagate `store`

#### Changed: `lib/MagicMountain/Activity/Prospecting.pm`

- Add `has _activity_type => sub { 'prospecting' };`
- `create` already sets `type => 'prospecting'` — unchanged

#### Changed: `lib/MagicMountain/Activity/MarketVisit.pm`

- Add `has _activity_type => sub { 'market_visit' };`

#### Changed: `lib/MagicMountain/Activity/BlackMarket.pm`

- Add `has _activity_type => sub { 'black_market' };`

#### Changed: `lib/MagicMountain.pm` — accessors

Add `has activities` and modify the three Activity accessors to pass
`store => $self->activities`:

```perl
has activities => sub ($self) {
    MagicMountain::Model::Activity->new(
        file => $self->dataDir . '/activities.json',
        log  => $self->log,
    );
};

has prospecting => sub ($self) {
    my $p = MagicMountain::Activity::Prospecting->new(
        store            => $self->activities,
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/prospecting.yml',
        log              => $self->log,
    );
    $p->load_content;
    return $p;
};

has market => sub ($self) {
    MagicMountain::Activity::MarketVisit->new(
        store            => $self->activities,
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/factions.yml',
        log              => $self->log,
    )->load_content;
};

has black_market => sub ($self) {
    MagicMountain::Activity::BlackMarket->new(
        store            => $self->activities,
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/flavor/black_market.yml',
        log              => $self->log,
    )->load_content;
};
```

The `file` parameter is passed because Model internally uses it for
version/mtime checks. Activity objects never write to it directly —
`_saveTable` delegation ensures all disk I/O goes through the store.

### Part B: Deferred Save Mode in Model.pm

Add a package-level deferred-save mechanism keyed by the shared table reference
(`0+$self->table`). When deferred, `_saveTable` skips the file write and marks
the table dirty. A `flush()` call writes once per dirty table.

```perl
my %_deferred_for;   # 0+$table => 1

sub _saveTable ($self) {
    return 1 if $_deferred_for{0+$self->table};
    # ... existing write logic unchanged (lines 128-156) ...
}

sub defer_saves ($self) {
    $_deferred_for{0+$self->table} = 1;
}

sub flush ($self) {
    my $key = 0+$self->table;
    return unless delete $_deferred_for{$key};
    $self->_saveTable;
}
```

The key uses the table hashref address, which is shared between the model
singleton and all child objects from `get()`/`create()`. This means deferring
on the store automatically defers all Activity subclass saves.

### Part C: Wrap Bot Loop with Defer/Flush

In `MagicMountain.pm`, around the bot processing loop inside `on_maintenance`:

```perl
if (@$bot_chars) {
    my @models = (
        $maint->app->activities,
        $maint->app->characters,
        $maint->app->shed,
    );
    push @models, $maint->app->pressures if $maint->app->can('pressures');
    $_->defer_saves for @models;

    # existing seed/shuffle/transcript setup
    for my $bot_char (@shuffled) {
        eval {
            $maint->app->bot_runner->run_day($bot_char);
        };
        ...
    }

    $_->flush for @models;
}
```

Because Prospecting, MarketVisit, and BlackMarket all delegate `_saveTable` to
`activities`, deferring on `activities` alone covers all three. Characters and
shed items are separate models and need their own defer.

### Unchanged

- `BotRunner.pm`, `advance_day.pm` — no changes
- Rest of maintenance flow (AP refresh, decay, climate, snapshots) — unchanged
- Transcript (JSONL append) — unaffected
- All dispatch handlers — `$self->save()`, `$self->create()`, `$self->get()`
  work identically through inherited Model methods

### Invariants

| Invariant | How it is satisfied |
|-----------|-------------------|
| One owner of persistence | `MagicMountain::Model::Activity` is the sole writer of `activities.json` |
| All types see same rows immediately | Shared table hashref across all Activity objects |
| Only owner defers/saves/flushes | Activity subclasses delegate `_saveTable` to store; cannot independently persist |
| Type filtering | `find`/`get` filtered by `_activity_type` in each subclass |
| Shared dirty state | `%_deferred_for` keyed on `0+$table` — same hashref = same defer flag |
| No mtime sync for intra-process | Shared table makes all changes visible without disk reads |

### Tests

Add unit tests for the defer/flush mechanism:

| Scenario | Checks |
|----------|--------|
| `defer_saves` → `save` → file unchanged | mtime or content unchanged |
| `defer_saves` → multiple `save`s → `flush` → all data present | all records on disk after flush |
| `defer_saves` → `delete` → `flush` → deletion persisted | deleted record absent after flush |
| `flush` on non-deferred model is safe | no-op, no crash |
| Double `defer_saves` is harmless | idempotent, no error |
| Two model instances sharing a table → defer on one, save on other, flush first → all data written | cross-type writes survive one flush |

Integration scenario: create prospecting + market_visit, defer, save both,
flush, verify both on disk.

### Expected Improvement

| Model       | Before   | After     |
|-------------|----------|-----------|
| Character   | ~55      | 1 write   |
| Prospecting | ~20      | 1 write   |
| MarketVisit | ~20      | 1 write   |
| Total time  | ~400ms   | ~50ms     |

### Implementation Sequence

1. `lib/MagicMountain/Model/Activity.pm` — new file
2. `lib/MagicMountain/Model.pm` — defer/flush
3. `lib/MagicMountain/Activity.pm` — store delegation, type filter
4. `lib/MagicMountain/Activity/Prospecting.pm` — `_activity_type`
5. `lib/MagicMountain/Activity/MarketVisit.pm` — `_activity_type`
6. `lib/MagicMountain/Activity/BlackMarket.pm` — `_activity_type`
7. `lib/MagicMountain.pm` — `activities` accessor, modify three accessors
8. `lib/MagicMountain.pm` — wrap bot loop with defer/flush
9. Tests
10. `make indent && make clean && prove -l t/`
11. Completion-checker and post-verify
