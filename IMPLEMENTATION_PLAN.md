# Prospecting Activity Rewrite — Implementation Plan

**Goal**: Align `Activity::Prospecting`, `Model::Character`, `Activity` base class,
controllers, routes, templates, and tests with the refactored architecture
described in `GAME_ARCHITECTURE.md`.

**Key architectural changes from the old spec:**

| Old | New |
|-----|-----|
| `turns_remaining` (per-character) | `action_points` / `action_points_max` (per-character) |
| Prospecting costs 1 turn | Prospecting costs 2 AP |
| `stop` → generates buyer offers (`offers` column), phase `awaiting_buyer` | `stop` → creates ShedItem, phase back to `idle`, no offers |
| `sell` action on prospecting activity | Removed (selling moved to MarketVisit activity) |
| Activity columns include `offers` | `offers` removed, `customer` added |
| Collapse formula: `ratio × 0.8` | Collapse formula: `ratio² × 0.95` |
| Default daily turns: 10 | Default action points: 15 |
| Routes: `/artifact/*`, `/sale/:faction_id` | Routes: `/prospecting/*` |

---

## Phase 0 — Foundation

### 0.1 Character Model Columns + All Writer/Reader Updates

**File**: `lib/MagicMountain/Model/Character.pm:7`

Rename `turns_remaining` → `action_points` in the columns list.

Add columns:
```
action_points_max       integer  (default 15)
skill_prospecting       integer  (0-3, default 0)
skill_upcycling         integer  (0-3, default 0)
skill_selling           integer  (0-3, default 0)
```

**API convention**: All character field access must use `getCol`/`setCol` methods,
not raw hashref access. Controllers pass the model instance (`$char_model`) to
`dispatch()`, and handlers access fields through the Model accessor API:
```perl
# Correct:
my $ap = $char->getCol('action_points');
$char->setCol('action_points', $ap - 2);

# Wrong — bypasses column validation:
$char->{action_points} -= 2;
```

**Persistence convention**: Activities own all persistence. Handlers call
`$self->save`, `$char->save`, and `$self->delete` (on terminal outcomes).
The controller never calls `save` or `delete` on any model — its sole job is
dispatch + render.

**Validation convention**: Add a `validate` hook to `Model.pm` called by `setCol`.
Override in `Model::Character` to enforce invariants. Dies on invalid assignment
— fails fast at the write site.

All character column dependencies must be updated atomically with the rename:

| File | Change |
|------|--------|
| `MagicMountain.pm:93-98` (maintenance) | `setCol('turns_remaining', ...)` → `setCol('action_points', ...)`. Use per-character `action_points_max` column — not the config default. Also update log message line 82: "turns" → "AP" |
| `MagicMountain.pm:30` (config) | `default_daily_turns` → `default_action_points`, value 15 |
| `Controller/Game.pm:25,32,43` | `daily_turns` var → `daily_ap`. `turns_remaining:` key → `action_points:` |
| `Controller/Game.pm:30` | Add `action_points_max => $daily_ap` |
| `templates/game/show.html.ep:28-30` | "Turns" → "AP" |
| `show.html.ep:98,103` | `STAT_TURNS` → `STAT_AP`, `p.turns_remaining` → `p.action_points` |
| `t/model_character.t:21,33,40,44,50` | `turns_remaining` → `action_points` in column list, test data, assertions. Add `action_points_max` where needed |
| `t/activity_prospecting.t` | `_fresh_char` uses `action_points => 15`. TestCharacter: `turns_remaining` → `action_points`. Assertions: `$char->{turns_remaining}` → `$char->getCol('action_points')` |
| `t/prospecting_web.t` | Character setup uses `action_points => 15` |

These must be done as a single unit — the codebase has no `turns_remaining` from
the moment Phase 0.1 starts.

### 0.1b Model Validation Hook

**Files**: `lib/MagicMountain/Model.pm` + `lib/MagicMountain/Model/Character.pm`

Add a `validate` hook to `Model.pm` called by `setCol` before assignment:

```perl
# Model.pm — add to setCol and new method
sub setCol ($self, $columnName, $optionalValue=undef) {
    if (grep {$_ eq $columnName} @{$self->columns}) {
        $self->validate($columnName, $optionalValue);
        return $self->row->{$columnName} = $optionalValue
    }
    die ("assert: no such column '$columnName' declared on " . ref $self);
}

sub validate ($self, $columnName, $value) { 1 }  # no-op base
```

Override in `Model/Character.pm` to enforce invariants:

```perl
sub validate ($self, $col, $val) {
    if ($col eq 'score' && defined($val) && defined($self->getCol('score'))
        && $val < $self->getCol('score')) {
        die "invariant: score must never decrease";
    }
    if ($col eq 'scrap' && defined($val) && $val < 0) {
        die "invariant: scrap must be non-negative";
    }
    if ($col eq 'action_points' && defined($val)) {
        my $max = $self->getCol('action_points_max') // 15;
        die "invariant: action_points ($val) exceeds max ($max)" if $val > $max;
    }
    if ($col =~ /^skill_/ && defined($val) && ($val < 0 || $val > 3)) {
        die "invariant: $col must be 0-3";
    }
}
```

### 0.2 Activity Base Columns

**File**: `lib/MagicMountain/Activity.pm:12-18`

Change columns declaration:
```
[ @$cols, qw(char_id type phase artifact offers) ]
→ [ @$cols, qw(char_id type phase artifact customer) ]
```

Remove `offers` accessor (lines 61-65). Add `customer` accessor:

```perl
sub customer {
    my $self = shift;
    return $self->setCol('customer', shift) if @_;
    return $self->getCol('customer');
}
```

### 0.3 New ShedItem Model

**File**: `lib/MagicMountain/Model/ShedItem.pm` (new)

Full subclass following the existing `MagicMountain::Model` pattern:

```perl
package MagicMountain::Model::ShedItem;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        char_id artifact_id
        original_value decayed_value condition days_in_shed
        instability stage push_count has_evolved
        behaviors archetypes
        estimated_value_min estimated_value_max
    )];
};

1;
```

`condition` is a plain string field (`fresh` / `settling` / `fading`). There is
no enum enforcement in `MagicMountain::Model` — validation is the caller's
responsibility.

### 0.4 App Class — Shed Attribute + `use` Import

**File**: `lib/MagicMountain.pm`

Add to the imports at line 16:
```perl
use MagicMountain::Model::ShedItem;
```

Add after the `characters` attribute:
```perl
has shed => sub ($self) {
    MagicMountain::Model::ShedItem->new(
        file => $self->dataDir . '/shed.json',
        log  => $self->log,
    );
};
```

---

## Phase 1 — Prospecting Activity Rewrite

### 1.1 Transition Table

**File**: `lib/MagicMountain/Activity/Prospecting.pm:7-13`

```perl
# Old:
{ idle => ['begin'], processing => ['push', 'stop'], awaiting_buyer => ['sell'] }

# New:
{ idle => ['begin'], processing => ['push', 'stop'] }
```

### 1.2 `begin` Handler

Change guard — use accessor:
```perl
die "AP exhausted" unless ($char->getCol('action_points') // 0) >= 2;
```

Change deduction — use setCol:
```perl
$char->setCol('action_points', $char->getCol('action_points') - 2);
```

Add persistence — handler saves both the activity row and the character,
and sets the FK so subsequent requests find this activity:
```perl
$char->setCol('pending_activity_id', $self->getCol('id'));
$self->save;
$char->save;

return {
    view => {
        ...
    },
};
```

### 1.2b `_player_snapshot`

**File**: `Prospecting.pm:109-114`

Replace raw hashref access with getCol calls:

```perl
# Old:
turns_remaining => $char->{turns_remaining},
scrap           => $char->{scrap} // 0,
score           => $char->{score} // 0,

# New:
action_points => $char->getCol('action_points'),
scrap         => $char->getCol('scrap'),
score         => $char->getCol('score'),
```

Must be done immediately after 1.2 so views don't return the wrong key name.

### 1.3 `push` Handler — Collapse Formula + Persistence

**File**: `Prospecting.pm:174-177`

```perl
# Old:
my $collapse_chance = $ratio * 0.8;
$collapse_chance = 1.0  if $collapse_chance > 1.0;
$collapse_chance = 0.05 if $collapse_chance < 0.05;

# New:
my $collapse_chance = ($ratio ** 2) * 0.95;
$collapse_chance = 1.0  if $collapse_chance > 1.0;
$collapse_chance = 0.05 if $collapse_chance < 0.05;
```

**Persistence**: On the normal (no collapse, no breakthrough) path, add saves:
```perl
$self->artifact($artifact);
$self->save;
$char->save;

return {
    view => {
        ok       => 1,
        result   => 'push',
        artifact => $self->_artifact_view($artifact),
        player   => $self->_player_snapshot($char),
    },
};
```
Collapse and breakthrough paths handle their own terminal persistence (see 1.6).

### 1.4 `stop` Handler — Complete Rewrite

**File**: `Prospecting.pm:213-245`

Old: Generate fake faction offers, set phase `awaiting_buyer`, persist offers.

New:
1. No AP cost (cost already deducted at `begin`)
2. Calculate estimated value range: `min = floor(value × 0.8)`, `max = floor(value × 1.2)`
3. Create ShedItem via `$self->app->shed->create(...)` with current artifact state
4. Call `$item->save` to persist the new ShedItem row
5. Set phase to `idle`, clear artifact
6. Delete own activity row: `$self->delete`
7. Clear FK and save char: `$char->setCol('pending_activity_id', undef)`; `$char->save`
8. Return view with shed item summary

The handler owns teardown completely — activity row deletion, FK clear, and
character persistence all happen inside the handler. The controller never calls
save or delete on any model.

```perl
my $item = $self->app->shed->create(
    char_id            => $char->getCol('id'),
    artifact_id        => $artifact->{id},
    original_value     => $artifact->{value},
    decayed_value      => $artifact->{value},
    condition          => 'fresh',
    days_in_shed       => 0,
    instability        => $artifact->{instability},
    stage              => $artifact->{stage},
    push_count         => $artifact->{push_count},
    has_evolved        => $artifact->{has_evolved},
    behaviors          => $artifact->{behaviors},
    archetypes         => $artifact->{archetypes},
    estimated_value_min => $est_min,
    estimated_value_max => $est_max,
);
$item->save;

# Activity owns teardown — delete own row, clear FK, save char
$self->delete;
$char->setCol('pending_activity_id', undef);
$char->save;

return {
    view => {
        ok        => 1,
        result    => 'stopped',
        shed_item => {
            id                   => $item->getCol('id'),
            artifact_id          => $artifact->{id},
            estimated_value_min  => $est_min,
            estimated_value_max  => $est_max,
            condition            => 'fresh',
        },
        player => $self->_player_snapshot($char),
    },
};
```

### 1.5 Remove `sell` Handler

Delete entire `sell` method (lines 247-273). Selling is now handled by `Activity::MarketVisit` (future).

### 1.6 Clean Up Internal Outcomes

- `_do_collapse`: Remove `$self->offers(undef)` line
- `_do_collapse`: No AP refund — `action_points` unchanged by collapse (correct)
- `_do_collapse`: Add terminal persistence — delete own row, clear FK, save char:
  ```perl
  $self->delete;
  $char->setCol('pending_activity_id', undef);
  $char->save;
  ```
- `_do_breakthrough`: Remove `$self->offers(undef)` line
- `_do_breakthrough`: Replace raw hashref access with getCol/setCol:
  ```perl
  # Old:
  $char->{scrap} += $new_value;
  $char->{score} += $new_value;

  # New:
  $char->setCol('scrap', $char->getCol('scrap') + $new_value);
  $char->setCol('score', $char->getCol('score') + $new_value);
  ```
- `_do_breakthrough`: Add terminal persistence — same as collapse:
  ```perl
  $self->delete;
  $char->setCol('pending_activity_id', undef);
  $char->save;
  ```
- Verify `action_points` not changed by breakthrough (correct — no AP refund or cost)

### 1.7 Update Defaults

**File**: `Prospecting.pm:82-87`

Align defaults with content/prospecting.yml (some already match, verify):

| Parameter | Current default | Spec default |
|-----------|----------------|--------------|
| max_instability | 12 | 14 (varies per spec) |
| instability_growth_max | 3 | 2 (varies) |
| base_gain_min | 2 | 3 (varies) |
| base_gain_max | 5 | 5 (varies) |
| evolution_chance | 0.08 | 0.03 (varies) |
| evolution_threshold | 0.50 | 0.25 (varies) |

These are just fallback defaults; actual values come from YAML. The YAML file
is already correct — these defaults only matter if a spec is missing a field.

---

## Phase 2 — Routes, Controllers, Config

### 2.1 Rename Artifact Controller

- **Rename** `lib/MagicMountain/Controller/Artifact.pm` → `lib/MagicMountain/Controller/Prospecting.pm`
- Package name change: `MagicMountain::Controller::Artifact` → `MagicMountain::Controller::Prospecting`
- Must be done BEFORE updating routes so Mojolicious can resolve `to => 'prospecting#...'`
- **Functional changes in `_activity_action`**:
  1. Pass `$char_model` (model instance) to `dispatch()` instead of `$char_model->row`
  2. Remove all save/delete persistence logic — activity handlers own persistence

  ```perl
  # Old:
  my $row = $char_model->row;
  my $id  = $row->{pending_activity_id};
  my $activity = $id && $p->get($id)
      ? $p->get($id)
      : $p->create(char_id => $row->{id});
  my $result = $activity->dispatch($row, $action, %params);

  if ($activity->phase eq 'idle') {
      $p->delete($activity->getCol('id'));
      $char_model->setCol('pending_activity_id', undef);
  } else {
      $activity->save;
      $char_model->setCol('pending_activity_id', $activity->getCol('id'));
  }
  $char_model->save;
  $self->render(json => $result->{view});

  # New:
  my $id  = $char_model->getCol('pending_activity_id');
  my $activity = $id
      ? $p->get($id)
      : $p->create(char_id => $char_model->getCol('id'));
  my $result = $activity->dispatch($char_model, $action, %params);
  $self->render(json => $result->{view});
  ```
  The controller is now a true dumb pipe — dispatch + render. Activity handlers
  own all persistence (character saves, activity saves/deletes, FK management).

### 2.2 Rename Routes

**File**: `lib/MagicMountain.pm:207-211`

```perl
# Old:
$auth->post('/artifact/begin')->to('artifact#begin');
$auth->post('/artifact/push')->to('artifact#push');
$auth->post('/artifact/stop')->to('artifact#stop');
$auth->post('/sale/:faction_id')->to('sale#create');

# New:
$auth->post('/prospecting/begin')->to('prospecting#begin');
$auth->post('/prospecting/push')->to('prospecting#push');
$auth->post('/prospecting/stop')->to('prospecting#stop');
```

### 2.3 Delete Sale Controller

**File**: `lib/MagicMountain/Controller/Sale.pm` — delete entire file.

---

## Phase 3 — Game State & Frontend

### 3.1 Game Controller

**File**: `lib/MagicMountain/Controller/Game.pm`

- Lines 52-55: Remove `offers_json` stash; remove `offers` from activity load block
  (column rename and config changes were already done in Phase 0.1)

### 3.2 Game Template

**File**: `templates/game/show.html.ep`

- Lines 65-72: Remove `awaiting_buyer` phase block (offers/sale UI)
- Lines 127-142: Remove `showOffers()` and `sell()` functions
- Lines 144-152: `begin()`: `/artifact/begin` → `/prospecting/begin`
- Lines 153-165: `push()`: `/artifact/push` → `/prospecting/push`
- Lines 167-174: `stop()`: `/artifact/stop` → `/prospecting/stop`
- Lines 176-183: Remove `sell()` function
- Lines 194-200: Remove `showOffers()` call on initial stash
  (AP label and stat variable renames were already done in Phase 0.1)

**Note — Post-stop shed display**: After a successful `stop`, the immediate
response includes the new shed item, and the JS calls `location.reload()`. On
reload, the Game controller shows the idle prospecting card ("Ready to prospect")
but has no way to display shed contents — the `Shed#index` controller is not
implemented yet. This is acceptable: the player sees the shed item in the stop
response and can continue playing. Full shed inventory display will be added
with the Shed controller in a later phase.

---

### 0.5 Foundation Model Tests

**File**: `t/model_validate.t` (new file)

Tests for the `Model::validate` hook and `Model::Character` override:

| Test | Code | Expected |
|------|------|----------|
| Base validate is no-op | `Model->setCol('id', 'x')` | Succeeds (no die) |
| Score decrease dies | `$char->setCol('score', 5); $char->setCol('score', 3)` | Dies with "invariant: score" |
| Score increase OK | `$char->setCol('score', 5); $char->setCol('score', 8)` | Succeeds |
| Score set on new char | `$char->setCol('score', 5)` | Succeeds (no previous value) |
| Negative scrap dies | `$char->setCol('scrap', -1)` | Dies with "invariant: scrap" |
| AP above max dies | `$char->setCol('action_points_max', 15); $char->setCol('action_points', 16)` | Dies with "invariant: action_points" |
| AP at max OK | `$char->setCol('action_points_max', 15); $char->setCol('action_points', 15)` | Succeeds |
| AP zero OK | `$char->setCol('action_points', 0)` | Succeeds |
| Skill below 0 dies | `$char->setCol('skill_prospecting', -1)` | Dies with "invariant: must be 0-3" |
| Skill above 3 dies | `$char->setCol('skill_prospecting', 4)` | Dies with "invariant: must be 0-3" |
| Skill at 3 OK | `$char->setCol('skill_prospecting', 3)` | Succeeds |
| Non-invariant column unchanged | `$char->setCol('name', 'bob')` | Succeeds (no validate interference) |

**File**: `t/model_delete.t` (new file)

Tests for `Model::delete` default-arg behavior:

| Test | Code | Expected |
|------|------|----------|
| delete with no arg | `$instance->delete` | Deletes own row from table, returns true |
| delete with explicit id | `$model->delete($id)` | Deletes row by id, backward compatible |
| delete on unsaved instance | `$instance->delete` where id is undef | Returns undef, no crash |
| row gone after delete | delete then `$model->get($id)` | Returns undef |

**File**: `t/model_shed_item.t` (new file)

Basic CRUD — create, save, load by id, find by char_id, delete.

---

## Phase 4 — Tests

### 4.0 Model::Character Invariant Integration

**File**: `t/model_character_invariants.t` (new file)

Integration-level tests that validate enforcement in a realistic sequence
(mimicking how handlers write to the character):

- Full prospecting lifecycle: begin → push → stop → check AP never went negative
- Breakthrough auto-cashout: verify score only increases, never decreases
- Multiple days of activity: AP refresh respects `action_points_max`
- Direct `$char->{score} = 5` bypass test: verify raw hashref access is not used
  (enforced by convention and code review, not by validate — validate only
  catches `setCol` calls)

### 4.1 Activity Base Tests

**File**: `t/activity.t`

- Remove tests at lines 66-71 (`offers` column/accessor tests)
- Add `customer` column/accessor tests
- Update columns assertion at line 44: `offers` → `customer`

### 4.2 Prospecting Unit Tests

**File**: `t/activity_prospecting.t`

- TestCharacter: Use `action_points` key (5 → 15 AP for fresh char)
- `turns exhausted` → `AP exhausted`, check `>= 2` not `> 0`
- Update `begin` test: verify 2 AP deducted (15 → 13), and that `$char->save` was called (character persisted)
- Remove `stop→awaiting_buyer` test (lines 320-338)
- Remove `sell` tests (lines 352-399)
- Remove `stop→sell` from `delete` test (lines 443-461)
- Remove `stop→sell` from full lifecycle test (lines 465-490)
- Add new `stop→ShedItem` test: verify ShedItem created with estimated value, and verify `$self->delete` removed the activity row from the table
- Update collapse formula test expectations (ratio² × 0.95)
- Update columns assertion: no `offers`, expect `customer`
- **New**: `begin` persistence test — after begin, verify activity row exists in `activities.json` and character AP persisted
- **New**: `push` persistence test — after normal push, verify `$self->save` persisted updated artifact state
- **New**: `stop` persistence test — after stop, verify activity row deleted from table, ShedItem created, character FK cleared

### 4.3 Web Integration Tests

**File**: `t/prospecting_web.t`

- Route URLs: `/artifact/begin` → `/prospecting/begin`
- Character setup: `turns_remaining` → `action_points`
- Remove sell step from full lifecycle test
- `begin` test: verify AP deducted by checking game state

---

## Execution Order

```
Phase 0.1  — Character columns + ALL reader/writer updates (atomic),
              convention blocks (getCol/setCol, activity-owned persistence)
              Character.pm, MagicMountain.pm (config + maintenance),
              Controller/Game.pm, templates/game/show.html.ep,
              test character fixtures
Phase 0.1b — Model validation hook (Model.pm setCol calls validate,
              Character.pm overrides with invariants)
Phase 0.2  — Activity base columns & accessors (offers→customer)
Phase 0.3 — ShedItem model (new file, MagicMountain::Model subclass)
Phase 0.4 — App shed attribute + use import
Phase 0.5 — Foundation model tests (delete default-arg, Character invariants, ShedItem CRUD)
  ↓
Phase 1.1 — Transition table (remove awaiting_buyer, sell)
Phase 1.2 — begin handler (AP check/deduction)
Phase 1.2b — _player_snapshot (must follow 1.2 immediately)
Phase 1.3 — push collapse formula (ratio² × 0.95)
Phase 1.4 — stop handler (ShedItem creation, no activity deletion)
Phase 1.5 — Remove sell handler
Phase 1.6 — Clean up offers references (collapse, breakthrough)
Phase 1.7 — Update default values
  ↓
Phase 2.1 — Rename Artifact → Prospecting controller (must precede route change)
Phase 2.2 — Routes (/artifact/* → /prospecting/*)
Phase 2.3 — Delete Sale controller
  ↓
Phase 3.1 — Game controller (remove offers stash only)
Phase 3.2 — Game template (remove sell UI, update URLs)
Phase 4.0 — Model::Character invariant integration tests
Phase 4.1 — Activity base tests
Phase 4.2 — Prospecting unit tests
Phase 4.3 — Web integration tests
```

Each phase can be verified with:
```
perl -c lib/MagicMountain/Activity/Prospecting.pm   # syntax check
prove -l t/activity_prospecting.t                    # unit tests
prove -l t/prospecting_web.t                         # web tests
prove -l t/                                           # full suite
```
