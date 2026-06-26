# Tuning Reference — Magic Mountain

Every tunable parameter in the game, where it lives, its current value, and
what it affects. Refer to this when adjusting game balance.

---

## 1. Application Config

**File**: `lib/MagicMountain.pm` → `defaultConfig` (hash). Override via
`magic_mountain.yml` at the repo root.

| Key | Default | What it controls |
|-----|---------|------------------|
| `end_of_day_hour` | `0` (midnight) | Hour (0–23) when daily maintenance fires. AP refresh, decay, Crier. |
| `maintenance_window_minutes` | `5` | How long write routes return 503 during maintenance. |
| `session_timeout_minutes` | `60` | Minutes of inactivity before a session expires. |
| `default_season_length` | `30` | Days in a season before end is recommended (not enforced — admin-triggered). |
| `default_action_points` | `15` | Daily AP cap for all players. |
| `secrets` | `[override-me]` | Session cookie signing key. **Set a real value in production.** |

---

## 2. Artifact Specs (prospecting.yml)

**File**: `content/prospecting.yml`

Each artifact spec defines its own push math, decay, and signals. Fields
with defaults are applied by `_apply_defaults()` in
`lib/MagicMountain/Activity/Prospecting.pm:95-121`.

| Field | Default | Per-artifact override in YAML | What it affects |
|-------|---------|-------------------------------|-----------------|
| `weight` | `1` | `weight: 10` | Draw probability (higher = more common). Total across all specs is the pool. |
| `base_value` | `5` | `base_value: 5` | Starting value before pushes. Skill Prospecting 1/2 adds +2 each. |
| `starting_instability` | `0` | `starting_instability: 0` | Instability at draw time. |
| `max_instability` | `14` | `max_instability: 14` | Denominator in collapse ratio. Higher = more pushes before collapse risk grows. |
| `instability_growth_min` | `1` | `instability_growth_min: 1` | Minimum instability added per push (before upcycling reduction). |
| `instability_growth_max` | `2` | `instability_growth_max: 2` | Maximum instability added per push (inclusive). |
| `base_gain_min` | `3` | `base_gain_min: 3` | Minimum value gained per push (before upcycling bonus). |
| `base_gain_max` | `5` | `base_gain_max: 5` | Maximum value gained per push (inclusive). |
| `can_evolve` | `undef` (false) | `can_evolve: true` | Whether breakthrough is possible on this spec. |
| `evolution_threshold` | `0.25` | `evolution_threshold: 0.25` | Minimum instability ratio before evolution check is attempted. |
| `evolution_chance` | `0.03` | `evolution_chance: 0.04` | Base probability per push (once threshold met). Upcycling 3 adds +0.02. |
| `evolution_instability_spike` | `3` | `evolution_instability_spike: 2` | Extra instability added on breakthrough (value spike, more exciting signal). |
| `breakthrough_multiplier_min` | `1.5` | `breakthrough_multiplier_min: 1.5` | Minimum multiplier applied to current value on breakthrough. |
| `breakthrough_multiplier_max` | `2.5` | `breakthrough_multiplier_max: 2.0` | Maximum multiplier applied to current value on breakthrough. |
| `state_thresholds.stable` | `0.30` | `stable: 0.35` | Ratio threshold: ratio <= this = "stable". |
| `state_thresholds.strained` | `0.65` | `strained: 0.70` | Ratio threshold: ratio <= this = "strained"; above = "unstable". |
| `decay_modifiers` | *(global defaults)* | *(see below)* | Per-artifact decay curve overrides. |
| `intro` | `''` | Per artifact | Flavor text shown on begin. |
| `signals` | *(none)* | Per stage | Array of flavor texts, randomly selected per push. |
| `collapse` | *(none)* | Per artifact | Array of flavor texts, randomly selected on collapse. |

**Decay modifier defaults** (applied when an artifact omits any field):

| Modifier | Default | What it affects |
|----------|---------|-----------------|
| `fresh_multiplier` | `1.0` | Value multiplier during `fresh` stage (days < settling_day). |
| `settling_multiplier` | `0.75` | Value multiplier floor in `settling` stage. Extrapolated into `fading`. |
| `fading_multiplier` | `0.40` | Floor multiplier once in `fading` stage (value will not drop below this). |
| `settling_day` | `2` | Day number when artifact transitions from `fresh` to `settling`. |
| `fading_day` | `5` | Day number when artifact transitions from `settling` to `fading`. Must be > settling_day. |

---

## 3. Collapse Math (hardcoded in Prospecting.pm)

**File**: `lib/MagicMountain/Activity/Prospecting.pm:221-223`

The collapse chance formula is **not** in YAML — it's hardcoded:

```
collapse_chance = (instability / max_instability)³ × 0.95
clamped to [0.05, 1.0]
```

| Constant | Value | What it affects |
|----------|-------|-----------------|
| Exponent | `3` | How steeply collapse risk accelerates. Cubic = low risk early, sharp cliff late. |
| Multiplier | `0.95` | Slightly below 1.0 so ratio=1.0 gives 95% (not 100%). |
| Min clamp | `0.05` | Always at least 5% collapse chance, even at ratio=0. |
| Max clamp | `1.0` | Caps at 100% (guaranteed collapse). |

---

## 4. Skill Effects (hardcoded in Prospecting.pm and MarketVisit.pm)

**Costs** are in `content/skills.yml` (level 1 = 10, level 2 = 25, level 3 = 50
scrap). **Mechanical effects** are hardcoded:

### Prospecting (`Prospecting.pm`)

| Level | Effect | Code location |
|-------|--------|---------------|
| 1 | `base_value` +2 | `_apply_defaults`, line 101 |
| 2 | `base_value` +2 more (total +4); `weight` ×2 for artifacts with base_value >= 8 | `_draw_artifact`, line 44 |
| 3 | `base_gain_min` +1, `base_gain_max` +1 | `_apply_defaults`, lines 108-109 |

### Upcycling (`Prospecting.pm`)

| Level | Effect | Code location |
|-------|--------|---------------|
| 1 | Instability growth reduced by 1 (min 1) | `push`, line 214 |
| 2 | Growth reduced by 2; value gain increased by 1 | `push`, lines 214, 243 |
| 3 | Growth reduced by 3; value gain increased by 2; evolution_chance +0.02 | `push`, lines 214, 243, 234 |

### Selling (`MarketVisit.pm` and `Prospecting.pm`)

| Level | Effect | Code location |
|-------|--------|---------------|
| 1 | Stop estimate range narrowed from ±20% to ±15% | `Prospecting.pm:stop`, line 279 |
| 2 | Irritation gain on mismatches eliminated (gain = 0) | `MarketVisit.pm:offer`, line 168 |
| 3 | Match multiplier increased from 1.2× to 1.4×; one `desired_behaviors` revealed to player | `MarketVisit.pm:offer`, line 152; `begin`, line 94 |

---

## 5. MarketVisit Mechanics (hardcoded in MarketVisit.pm)

**File**: `lib/MagicMountain/Activity/MarketVisit.pm`

| Parameter | Value | Code location | What it affects |
|-----------|-------|---------------|-----------------|
| Standing weight coefficient | `1.0 + standing × 0.5` | `_weighted_faction`, line 37 | Higher standing = more likely to see that faction's buyer. |
| Standing price bonus | `+0.05 × standing` per point | `begin`, line 81 | Added to `base_multiplier` for pricing. |
| Match multiplier (sell < 3) | `1.2` | `offer`, line 152 | × base_multiplier when artifact matches desired_behaviors. |
| Match multiplier (sell >= 3) | `1.4` | `offer`, line 152 | Same, with Selling skill 3. |
| Mismatch multiplier | `0.5` | `offer`, line 166 | × base_multiplier when no behavior match. |
| Irritation threshold | `5` | `begin`, line 90 | Customer storms off when irritation reaches this. |
| Irritation gain per mismatch (sell < 2) | `1` | `offer`, line 167 | Incremented per mismatch offer. |
| Irritation gain (sell >= 2) | `0` | `offer`, line 168 | Selling 2 eliminates irritation gain. |
| Settle chance (default) | `0.15` | `begin`, line 91 | Probability customer accepts lowball on mismatch. Per-faction override in YAML. |
| Standing delta (match) | `+2` | `_do_sale`, line 258 | Standing gained on matched sale. |
| Standing delta (mismatch) | `+1` | `_do_sale`, line 258 | Standing gained on mismatched sale. |
| Standing bonus (evolved) | `+1` | `_do_sale`, line 259 | Extra standing if the sold artifact had a breakthrough. |

---

## 6. Faction Definitions (factions.yml)

**File**: `content/factions.yml`

| Field | Meaning | Tuning note |
|-------|---------|-------------|
| `id` | Internal key | Must match keys in `standing` and `faction_sales`. |
| `name` | Display name | Used in UI and Crier. |
| `interests` | Array of trait strings | Matched against artifact `behaviors`. More interests = wider match range. |
| `base_multiplier` | Float | Core pricing scalar. Adjusted by standing bonus (see §5). |
| `settle_chance` | Float (optional) | Per-faction override for settle probability. Falls back to 0.15 if absent. |

---

## 7. Shed & Decay (ShedManager.pm)

**File**: `lib/MagicMountain/ShedManager.pm`

| Parameter | Value | Code location | What it affects |
|-----------|-------|---------------|-----------------|
| `estimated_value_min` | `floor(decayed_value × 0.8)` | `apply_decay`, line 69 | Lower bound shown to player. Selling 1 narrows range (×0.85 instead). |
| `estimated_value_max` | `floor(decayed_value × 1.2)` | `apply_decay`, line 70 | Upper bound shown to player. Selling 1 narrows (×1.15). |

Decay formula and modifier defaults are documented in §2 (decay_modifiers) —
the same defaults live in ShedManager.pm lines 8-14 as a fallback when an
artifact has no decay_modifiers.

---

## 8. Crier (Crier.pm + crier.yml)

**File**: `lib/MagicMountain/Crier.pm` (priority logic), `content/flavor/crier.yml` (templates)

| Parameter | Value | Code location | What it affects |
|-----------|-------|---------------|-----------------|
| Priority levels | `faction_dominance:5, faction_surge:4, milestone:3, faction_slump:2, season_opening:1, generic:0` | `Crier.pm`, lines 8-15 | Higher priority messages override lower ones when multiple triggers fire. |
| Milestone thresholds | `10, 25, 63, 158...` (×2.5 each step) | `generate`, line 103 | Every time artifacts_received crosses a threshold, a milestone message fires. |
| Message templates | All strings in `crier.yml` | Content file | Template variables `{faction}`, `{influence}`, `{count}`, `{influence_gain}` are filled from season state. |

---

## 9. Character Invariants (hardcoded in Model/Character.pm)

**File**: `lib/MagicMountain/Model/Character.pm:10-25`

| Invariant | Enforcement |
|-----------|-------------|
| `score` never decreases | Die on setCol if new value < current value |
| `scrap` >= 0 | Die on setCol if new value < 0 |
| `action_points` <= `action_points_max` | Die on setCol if exceeded |
| `skill_*` columns 0–3 | Die on setCol if out of range |

---

## Quick-Start: What to Tune First

| Goal | Tune this |
|------|-----------|
| Players push more often before stopping | Lower `instability_growth_min/max` or raise `max_instability` in prospecting.yml |
| Collapse feels less punishing | Lower the exponent in collapse formula (Prospecting.pm:221) from 3 to 2 |
| Market feels more dynamic | Raise average `base_multiplier` in factions.yml, or lower `settle_chance` |
| Season feels longer/shorter | Change `default_season_length` in config (or CLI `create-season --length`) |
| Skills feel more impactful | Adjust skill costs in skills.yml, or the hardcoded effect deltas |
| Decay pushes players to sell sooner | Lower `fading_multiplier` or lower `fading_day` in prospecting.yml specs |
| Factions feel more differentiated | Give each faction a distinct `settle_chance` and adjust `interests` |
