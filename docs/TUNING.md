# Tuning Reference — Magic Mountain

Every tunable parameter in the game, where it lives, its current value, and
what it affects. Refer to this when adjusting game balance.

---

## 1. Application Config

**File**: `lib/MagicMountain.pm` → `defaultConfig` (hash). Override via
`magic_mountain.yml` at the repo root.

| Key | Default | What it controls |
|-----|---------|------------------|
| `secrets` | `[override-me]` | Session cookie signing key. **Set a real value in production.** |
| `end_of_day_hour` | `0` (midnight) | Hour (0–23) when daily maintenance fires. AP refresh, decay, Crier. |
| `maintenance_window_minutes` | `5` | How long write routes return 503 during maintenance. |
| `session_timeout_minutes` | `60` | Minutes of inactivity before a session expires. |
| `default_season_length` | `30` | Days in a season before end is recommended (not enforced — admin-triggered). |
| `default_season_label_prefix` | `Season` | Prefix for auto-generated season labels (e.g. "Season 1"). |
| `default_action_points` | `20` | Daily AP cap for all players. |
| `default_daily_turns` | `10` | Daily turn cap (legacy; AP is the primary resource). |

### Rate Limiting

| Key | Default | What it controls |
|-----|---------|------------------|
| `rate_limit_max_attempts` | `5` | Max failed logins per IP before block. |
| `rate_limit_max_attempts_per_name` | `5` | Max failed logins per username before block. |
| `rate_limit_window_minutes` | `15` | Sliding window for rate limit counting. |
| `rate_limit_block_minutes` | `15` | How long a blocked IP/username stays blocked. |
| `rate_limit_cleanup_interval` | `300` | Seconds between stale rate-limit entry cleanup. |
| `rate_limit_trusted_proxies` | `0` | Number of trusted reverse-proxy hops for IP detection. |

### Market Dynamics

| Key | Default | What it controls |
|-----|---------|------------------|
| `market_trait_saturation_rate` | `0.01` | Per-sale increase in trait saturation (1% each). |
| `market_max_saturation_discount` | `0.50` | Maximum price discount from trait saturation (50%). |
| `market_post_appetite_penalty` | `0.50` | Price penalty multiplier after faction appetite is exhausted. |
| `market_desperation_bonus` | `1.30` | Price bonus multiplier for artifacts that have sat unsold (idle). |
| `market_counter_offers` | `1` | Enable (`1`) / disable (`0`) counter-offers from buyers. |
| `market_multi_item` | `1` | Enable (`1`) / disable (`0`) multi-item sales per visit. |
| `faction_max_stars` | `5` | Maximum standing stars with any faction. |

### Bots / NPCs

| Key | Default | What it controls |
|-----|---------|------------------|
| `bots.count` | `0` | Number of AI NPC competitors to seed at season start. 0 = disabled. |
| `bots.profiles` | `[]` | Array of `{id: profile_id}` entries from `content/bots.yml`. Cycled through if count exceeds profile list. |
| `bots.action_points` | *(falls back to `default_action_points`)* | Daily AP for bot characters (defaults to same as human players). |

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
| 4 | Initial instability reduced by upcycling level; growth reduced by 4; value gain increased by 3 | `_apply_defaults`, line 102; `push` |

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
| `skill_*` columns 0–4 | Die on setCol if out of range |

---

## 10. Account Config

**File**: `MagicMountain.pm` defaultConfig, `magic_mountain.yml`

| Parameter | Default | What it affects |
|-----------|---------|-----------------|
| `admin_email` | `root@localhost` | Shown on the recovery code page as contact for admin token reset. |
| `bcrypt_cost` | `10` | Cost factor for bcrypt token hashing. Higher = slower to verify. |

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
