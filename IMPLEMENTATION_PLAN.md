# Artifact Decay — Implementation Plan

**Goal**: Implement artifact decay in the Shed — condition stages, smooth daily
value degradation, estimated value updates, and trait-specific decay modifiers.

**Design constraint**: Decay runs during daily maintenance, not per-action.
Shed items are self-contained snapshots (decay modifiers are copied from the
artifact spec at stop time, like behaviors/archetypes already are).

---

## Design Summary (Per User Decisions)

| Decision | Choice |
|----------|--------|
| Decay configuration | Per-artifact `decay_modifiers` in `content/prospecting.yml` |
| Decay curve | Smooth daily decay — linear interpolation between modifier points |
| Day thresholds | Per-artifact only (`settling_day`, `fading_day`). No global defaults |
| Estimate updates | Recalculate from `decayed_value` using ±20% formula |
| Decay state tracking | Track `decay_multiplier` on shed item for future faction matching |

### Decay Formula

Each shed item stores its artifact's `decay_modifiers` hash (copied at stop
time). On each maintenance tick, for each shed item:

1. **Increment** `days_in_shed` by 1 → `d`
2. **Compute decay_multiplier** using the artifact's modifiers:

```
mods = shed_item.decay_modifiers
d    = shed_item.days_in_shed

if d < mods.settling_day:
    condition = 'fresh'
    mult      = mods.fresh_multiplier

elif d < mods.fading_day:
    condition = 'settling'
    progress  = (d - mods.settling_day) / (mods.fading_day - mods.settling_day)
    mult      = mods.fresh_multiplier
              + progress * (mods.settling_multiplier - mods.fresh_multiplier)

else:  # d >= mods.fading_day
    condition = 'fading'
    # Continue linear decline at same slope as settling segment
    slope     = (mods.settling_multiplier - mods.fresh_multiplier)
              / (mods.fading_day - mods.settling_day)
    mult      = mods.settling_multiplier + (d - mods.fading_day) * slope
    mult      = max(mult, mods.fading_multiplier)   # floor
```

3. **Apply**: `decayed_value = floor(original_value × mult)`
4. **Update estimates**:
   `estimated_value_min = floor(decayed_value × 0.8)`
   `estimated_value_max = floor(decayed_value × 1.2)`
5. **Store**: `ShedItem.setCol('condition', condition)`,
   `ShedItem.setCol('decayed_value', decayed_value)`, etc., then `save()`

**Constraint**: `fading_day` must be at least `settling_day + 1` (minimum
1-day settling window). The `_decay_modifiers` helper enforces this at
construction time — if violated, the modifier set is rejected.

### Default modifiers (when artifact spec omits `decay_modifiers`):

```yaml
decay_modifiers:
  fresh_multiplier:     1.0
  settling_multiplier:  0.75
  fading_multiplier:    0.40
  settling_day:         2
  fading_day:           5
```

---

## Phase 1 — Content & Column Updates

### 1.1 Add `decay_modifiers` to Artifact Specs

**File**: `content/prospecting.yml`

Add a `decay_modifiers` block to each artifact definition. Three artifacts
means three modifiers blocks, each tuned to the artifact's personality:

```yaml
decay_modifiers:
  fresh_multiplier:     1.0
  settling_multiplier:  0.75
  fading_multiplier:    0.40
  settling_day:         2
  fading_day:           5
```

All three artifacts can start with identical defaults; they become tuning
knobs during balance testing.

### 1.2 Add `decay_modifiers` Column to ShedItem

**File**: `lib/MagicMountain/Model/ShedItem.pm`

Add `decay_modifiers` to the columns list. This stores the hashref snapshot
copied from the artifact spec at stop time.

### 1.3 Apply Defaults in `_apply_defaults` (Not `stop`)

**File**: `lib/MagicMountain/Activity/Prospecting.pm` — `_apply_defaults()`

Add `decay_modifiers` to the `_apply_defaults` helper (line 71), alongside
the other spec-field defaults. This ensures the field is present on the live
artifact hash for any handler that needs it (including `stop`):

```perl
$artifact->{decay_modifiers} //= { ... defaults ... };
```

### 1.4 `_decay_modifiers` Helper for Defaults

Add a helper that returns a fully-populated modifiers hash from an artifact
spec, filling in defaults for any omitted key and validating the constraints
(`fading_day > settling_day`). Called by `_apply_defaults`.

---

## Phase 2 — Decay Engine

### 2.1 `MagicMountain::ShedManager` Service Class

**File**: `lib/MagicMountain/ShedManager.pm` (new)

A service class that owns decay logic and shed-level operations. Not a Model
subclass — it wraps `Model::ShedItem` for persistence. Distinct from the
`$app->shed` model accessor (which is `Model::ShedItem` CRUD).

```perl
package MagicMountain::ShedManager;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub apply_decay ($self) { ... }    # iterates all items, applies one tick
```

**`apply_decay()` method**:

1. Load all shed items: `$self->app->shed->load;`
2. Get all rows from `$self->app->shed->table`
3. For each row:
   a. Increment `days_in_shed`
   b. Compute condition, decay_multiplier via decay formula
   c. Set `condition`, `decayed_value`, `estimated_value_min`, `estimated_value_max`
   d. `$item->save`
4. Log total decayed items

**Static/composable decay function** for testability:

```perl
sub compute_decay ($class, $days_in_shed, $modifiers) {
    ...
    return ($condition, $multiplier);
}
```

### 2.2 App Wiring

**File**: `lib/MagicMountain.pm`

Add the import alongside the other model imports (line ~18):

```perl
use MagicMountain::ShedManager;
```

Add the attribute:

```perl
has shed_manager => sub { MagicMountain::ShedManager->new(app => shift) };
```

### 2.3 Decay Math Tests

**File**: `t/decay.t` (new)

| Test Case | Input | Expected |
|-----------|-------|----------|
| Fresh (day 0) | days=0, defaults | condition=fresh, mult=1.0 |
| Pre-settling (day 1) | days=1, defaults | condition=fresh, mult=1.0 |
| Settling start (day 2) | days=2, defaults | condition=settling, mult=0.75 → ... linear trend starts |
| Mid-settling (day 3) | days=3, defaults | interpolated between fresh(1.0) and settling(0.75) |
| Fading start (day 5) | days=5, defaults | condition=fading, mult=0.75 (still at settling because slope just started... actually at fading_day the mult is settling_multiplier, then continues declining) |
| Deep fading (day 10) | days=10, defaults | condition=fading, mult asymptotically approaching 0.4 |
| Custom thresholds | custom settling/fading days | Correct boundary hits |
| Zero original_value | any | decayed_value stays 0 |
| Edge: settling_day == fading_day | same day | No settling window, jumps to fading |
| Default fallback | no modifiers hash | Uses global defaults |

---

## Phase 3 — Maintenance Integration

### 3.1 Update `on_maintenance` Callback

**File**: `lib/MagicMountain.pm`, the `on_maintenance` closure in the
`maintenance` attribute.

Add after the AP refresh loop:

```perl
$maint->app->shed_manager->apply_decay;
```

Location matters: decay should run after AP refresh and day increment, but
before the season-length warning. The full maintenance order becomes:

1. Increment `season.day`
2. Refresh all character AP
3. **Apply artifact decay** (new)
4. Warn if day exceeds season length

### 3.2 Integration Test

**File**: `t/maintenance.t`

Extend the existing maintenance test to:
- Create a shed item for a character with known values
- Trigger maintenance (simulate time advancing past next_run)
- Verify the shed item's `days_in_shed` incremented, `decayed_value` decreased,
  `condition` advanced, estimates updated
- Run maintenance again (second tick) and verify compounding

---

## Phase 4 — Transcript & Faction Readiness

### 4.1 Decay Events (Optional, Flag-Gated)

`ShedManager` has a `log_transcript` flag (default 0). When enabled,
`apply_decay` logs a `decay_tick` event per item per tick:

```json
{
  "type": "decay_tick",
  "shed_item_id": "<uuid>",
  "artifact_id": "thermal_box_001",
  "char_id": "<uuid>",
  "days_in_shed": 3,
  "condition": "settling",
  "decayed_value": 8,
  "multiplier": 0.85,
  "narrative": "Thermal box day 3: settling (value 8, mult 0.85)."
}
```

The simulate command enables this automatically for tuning analysis:
```perl
$app->shed_manager->log_transcript(1);
```

### 4.2 Faction-Ready Decay State

The `condition` and `decayed_value` fields on shed items are now dynamic.
Future faction matching can reference `condition` as a trait filter
(e.g., Purifiers pay premium for `fading` items). No additional schema
changes needed beyond `decay_modifiers` and the dynamic `condition`.

---

## Execution Order

```
Phase 1.1 — Add decay_modifiers to content/prospecting.yml
Phase 1.2 — Add decay_modifiers column to ShedItem model
Phase 1.3 — Add decay_modifiers defaults in Prospecting::_apply_defaults
Phase 1.4 — Create _decay_modifiers helper for defaults + validation
  ↓
Phase 2.1 — Create MagicMountain::ShedManager with compute_decay + apply_decay
Phase 2.2 — App wiring (use + has shed_manager)
Phase 2.3 — Decay math tests
  ↓
Phase 3.1 — Integrate apply_decay into Maintenance on_maintenance
Phase 3.2 — Maintenance integration tests
  ↓
Phase 4.1 — decay_tick transcript events
Phase 4.2 — Ready for faction condition matching (no code change needed)
```

Each phase can be verified with:
```
perl -Ilib -wc lib/MagicMountain/ShedManager.pm    # syntax + warnings
prove -l t/decay.t                                  # decay math tests
prove -l t/maintenance.t                            # integration test
prove -l t/                                         # full suite
```
