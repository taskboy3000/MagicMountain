# Magic Mountain — Content File Reference

This document describes every YAML file in `content/` and every parameter.
All files are human-readable and tuneable. No code changes are needed to
add artifacts, factions, skills, bot profiles, or narrative text.

---

## 1. `content/factions.yml`

Defines the five factions that buy artifacts at the Bazaar.

```yaml
factions:
  - id: syndicate              # Unique key, used in code lookups
    name: "The Syndicate"      # Display name shown to players
    interests:                 # Artifact behaviors this faction wants to buy
      - thermal                #   (match if artifact has any of these tags)
      - storage
      - food_processing
      - power
    base_multiplier: 1.1       # Offer price multiplier before standing bonuses
```

### Fields

| Field | Required | Type | Default | Description | Tuning |
|-------|----------|------|---------|-------------|--------|
| `id` | yes | string | — | Internal key | Must match any bot profile references. Keep stable once set |
| `name` | yes | string | — | Display name in the UI | Cosmetic only |
| `interests` | yes | list of strings | — | Artifact behaviors this faction buys. Match if ANY artifact behavior matches | **Widen** → faction buys more artifacts, higher match rate. **Narrow** → faction is more selective, lower loyalist viability. Recommend 3–5 interests per faction, drawn from the actual artifact pool |
| `base_multiplier` | yes | float | — | Base offer scalar. Final = `decayed_value × multiplier × match_mult` (match_mult=1.2 or 0.5) | **Higher** → more scrap per sale, stronger faction. Range 0.8–1.3 typical. Purifiers (1.2) pay well but have narrow interests. LibreMount (0.9) pays poorly but wants common artifacts |
| `settle_chance` | no | float 0–1 | 0.15 | Probability faction accepts a mismatch offer | **Higher** → more sales via settlement. Caps at ~0.30 before it feels like the faction isn't selective |
| `disposition` | no | string | — | Flavor tag shown in UI | Cosmetic only. "commercial_resale", "scholarly", "destruction", etc. |

---

## 2. `content/prospecting.yml`

Defines every artifact that can be drawn from the mountain.

```yaml
- id: thermal_box_001          # Unique artifact key
  behaviors: [thermal, power]  # Tags for faction interest matching
  weight: 10                   # Draw probability weight (higher = more common)
  base_value: 5                # Starting value before pushes
  starting_instability: 0      # Always 0
  max_instability: 14          # Instability ceiling for ratio calculation
  instability_growth_min: 1    # Min instability added per push
  instability_growth_max: 2    # Max instability added per push (inclusive)
  base_gain_min: 3             # Min value increase per push
  base_gain_max: 5             # Max value increase per push (inclusive)
  can_evolve: true             # Can this breakthrough?
  evolution_threshold: 0.25    # Min instability ratio to attempt evolution
  evolution_chance: 0.04       # Probability of breakthrough per eligible push
  evolution_instability_spike: 2  # Extra instability on breakthrough
  breakthrough_multiplier_min: 1.5   # Min value multiplier on breakthrough
  breakthrough_multiplier_max: 2.0   # Max value multiplier on breakthrough
  state_thresholds:            # Ratio boundaries for stage labels
    stable: 0.35               #   ratio <= stable → "stable"
    strained: 0.70             #   ratio <= strained → "strained"
                               #   ratio > strained → "unstable"
  decay_modifiers:             # Optional. How shed decay affects this artifact
    fresh_multiplier: 1.0      #   Value multiplier while condition == "fresh"
    settling_multiplier: 0.75  #   Value multiplier while condition == "settling"
    fading_multiplier: 0.40    #   Floor multiplier while condition == "fading"
    settling_day: 2            #   Day in shed when condition becomes "settling"
    fading_day: 5              #   Day in shed when condition becomes "fading"
  intro: "The box is warm..."  # Flavor text shown when first drawn
  signals:                     # Per-stage flavor text (picks randomly)
    stable: ["...", "..."]     #   At least 2 per stage recommended
    strained: ["...", "..."]
    unstable: ["...", "..."]
  collapse: ["...", "..."]     # Flavor text on artifact collapse
```

### How an artifact works

1. **Drawing**: Weighted random from all artifacts. Total weight sums across
   all specs. Prospecting skill 2 doubles weight for artifacts with
   `base_value >= 8`.

2. **Pushing**: Each push adds `instability_growth_min..instability_growth_max`
   to instability and `base_gain_min..base_gain_max` to value. Pushing also
   increments `push_count`.

3. **Collapse**: Checked every push. Probability = `(instability/max_instability)³ × 0.95`,
   clamped to [0.05, 1.0]. On collapse: artifact destroyed, no payout.

4. **Breakthrough**: If collapse didn't happen and `can_evolve` is true and
   ratio >= `evolution_threshold` and random roll < `evolution_chance`:
   value = value × random(`breakthrough_multiplier_min`, `max`), awarded
   immediately as scrap+score. Instability spikes by
   `evolution_instability_spike`.

5. **Stop**: Player halts. ShedItem created with current value. Decay starts.

6. **Skill effects** (applied automatically):
   - Prospecting 1: `base_value + 2`
   - Prospecting 2: `base_value + 4`
   - Prospecting 3: `base_gain_min + 1`, `base_gain_max + 1`
   - Upcycling 1-3: instability growth reduced by skill level (min 1)
   - Upcycling 2: value gain per push +1
   - Upcycling 3: `evolution_chance + 0.02`

### Fields

| Field | Required | Type | Default | Description | Tuning |
|-------|----------|------|---------|-------------|--------|
| `id` | yes | string | — | Unique artifact key | Must be unique across all artifacts |
| `behaviors` | yes | list of strings | — | Tags for faction interest matching | **More tags** → matches more factions → sells faster. **1–2 tags** is typical. 2 is safer for balance |
| `weight` | yes | integer | — | Draw probability (higher = more common) | Total pool weight = sum of all weights. **Higher** → more common. **Lower** → rarer. Ranges 2–15 are practical. Most artifacts should be weight 5–8 |
| `base_value` | yes | integer | — | Starting value before pushes | **Higher** → more valuable baseline. Prospecting skill adds +2 per level. Typical range 3–10 |
| `max_instability` | yes | integer | — | Ratio ceiling for instability/max | **Higher** → more pushes before collapse risk ramps up. Typical range 10–16 |
| `instability_growth_min` | yes | integer | — | Minimum instability per push | **Higher** → faster instability growth → riskier. Typical 1–2 |
| `instability_growth_max` | yes | integer | — | Maximum instability per push (inclusive) | **Higher** → more variance in risk per push. Typical 2–3 |
| `base_gain_min` | yes | integer | — | Minimum value gained per push | **Higher** → richer per push. Prospecting 3 adds +1. Typical 3–5 |
| `base_gain_max` | yes | integer | — | Maximum value gained per push (inclusive) | **Higher** → more value variance. Typical 5–8 |
| `can_evolve` | yes | boolean | — | Whether breakthrough is possible | `true` for most artifacts. Breakthrough is exciting. A few non-evolvable cheap artifacts add texture |
| `evolution_threshold` | yes | float 0–1 | — | Minimum instability/ratio for evolution check | **Lower** → breakthrough possible earlier. Typical 0.20–0.40 |
| `evolution_chance` | yes | float 0–1 | — | Breakthrough probability per eligible push | **Higher** → breakthrough more likely. Typical 0.03–0.07. Above 0.10 makes breakthrough feel common, reducing tension |
| `evolution_instability_spike` | yes | integer | — | Instability added on breakthrough | **Higher** → breakthrough itself is riskier (may still collapse!). Typical 2–3 |
| `breakthrough_multiplier_min` | yes | float | — | Minimum value multiplier on breakthrough | **Higher** → bigger payout. Typical 1.5–2.0 |
| `breakthrough_multiplier_max` | yes | float | — | Maximum value multiplier on breakthrough | Range between min and max creates payout variance. Typical 2.0–3.0 |
| `state_thresholds.stable` | yes | float 0–1 | — | Ratio ≤ this → stage "stable" | **Lower stable** → artifact reaches strained/unstable faster. Affects narrative timing only |
| `state_thresholds.strained` | yes | float 0–1 | — | Ratio ≤ this → stage "strained" | Gap between stable and strained determines "middle ground" window. Typical gap 0.25–0.35 |
| `decay_modifiers` | no | map | defaults | How shed decay affects this type | Omit for standard decay. Override for rare artifact types that decay differently |
| `decay_modifiers.fresh_multiplier` | no | float | 1.0 | Value multiplier while fresh | Rarely changed. Only for artifacts that lose value even when fresh |
| `decay_modifiers.settling_multiplier` | no | float | 0.75 | Value while settling | **Lower** → decays faster. Range 0.60–0.85 |
| `decay_modifiers.fading_multiplier` | no | float | 0.40 | Floor value while fading | **Lower** → artifacts become nearly worthless. **Higher** → decay has less sting. Range 0.25–0.50 |
| `decay_modifiers.settling_day` | no | integer | 2 | Day settling begins | **Lower** → decay starts sooner. **Higher** → more "fresh" time. Range 1–4 |
| `decay_modifiers.fading_day` | no | integer | 5 | Day fading begins (must be > settling_day) | Gap between settling_day and fading_day = gradual decay window. Typical gap 3–6 |
| `intro` | yes | string | — | First-draw flavor text | Cosmetic. One sentence |
| `signals.stable` | yes | list of strings | — | Flavor during stable stage | Cosmetic. 2–4 recommended. Picks randomly each push |
| `signals.strained` | yes | list of strings | — | Flavor during strained stage | Cosmetic. 2–4 recommended |
| `signals.unstable` | yes | list of strings | — | Flavor during unstable stage | Cosmetic. 2–4 recommended. Should feel intense/high-stakes |
| `collapse` | yes | list of strings | — | On-collapse flavor text | Cosmetic. 1–3 recommended |

### Decay formula (applied daily during maintenance)

```
d = days_in_shed (incremented by 1 each tick)

if d < settling_day:
    condition = "fresh"
    mult = fresh_multiplier
elif d < fading_day:
    condition = "settling"
    progress = (d - settling_day) / (fading_day - settling_day)
    mult = fresh_multiplier + progress × (settling_multiplier - fresh_multiplier)
else:
    condition = "fading"
    slope = (settling_multiplier - fresh_multiplier) / (fading_day - settling_day)
    mult = settling_multiplier + (d - fading_day) × slope
    mult = max(mult, fading_multiplier)

decayed_value = floor(original_value × mult)
```

---

## 3. `content/skills.yml`

Defines purchasable seasonal skills.

```yaml
skills:
  - id: prospecting              # Internal key, used in character columns
    name: Prospecting            # Display name
    description: "Find better..." # Shown in UI below name
    max_level: 3                 # Maximum purchasable level (0–3)
    levels:                      # Cost per level (in scrap)
      - level: 1
        cost: 10
        description: "Better leads"     # Level-specific flavor (UI only)
      - level: 2
        cost: 25
        description: "Richer veins"
      - level: 3
        cost: 50
        description: "Eye for the unusual"
```

### Mechanical effects (hardcoded, not in YAML)

| Skill | Level | Effect |
|-------|-------|--------|
| prospecting | 1 | `base_value + 2` on drawn artifact |
| prospecting | 2 | `base_value + 4`; weight ×2 for `base_value ≥ 8` |
| prospecting | 3 | `base_gain_min + 1`, `base_gain_max + 1` per push |
| upcycling | 1 | instability growth −1 per push (min 1) |
| upcycling | 2 | growth −2; value gain per push +1 |
| upcycling | 3 | growth −3; value gain +2; `evolution_chance + 0.02` |
| selling | 1 | Estimate range narrowed from ±20% to ±15% at stop |
| selling | 2 | No irritation gain on mismatches at market |
| selling | 3 | Match mult 1.4× instead of 1.2×; reveals one desired behavior |

---

## 4. `content/bots.yml`

Defines bot strategy profiles used by the simulation system.

```yaml
- id: stage_guard_opportunist    # Profile key, used in --profile-weights
  display_name: "Cautious"       # Human-readable label
  push_policy:                   # Push strategy (see table below)
    name: "stage_guard"          #   Policy name
    params:                      #   Policy-specific parameters
      stop_at: "unstable"        #     (varies by policy)
  sell_policy:                   # Sell strategy (see table below)
    name: "opportunist"
    params: {}
  skill_profile:                 # Starting skill levels for this bot
    prospecting: 0
    upcycling: 0
    selling: 0
```

### Push policies

| Policy name | Params | Description |
|-------------|--------|-------------|
| `fixed_pushes` | `max` (default 3) | Push exactly N times, then stop |
| `instability_cap` | `max` (default 5) | Stop when instability exceeds cap |
| `stage_guard` | `stop_at` (default "unstable") | Stop when stage matches target |
| `greed` | `prob` (default 0.7) | Continue with probability P; stop with 1−P each push |
| `value_target` | `min` (default 20) | Stop when value exceeds target |
| `composite_and` | `policies` (list) | Stop when ALL sub-policies say stop |
| `composite_or` | `policies` (list) | Stop when ANY sub-policy says stop |

### Sell policies

| Policy name | Params | Description |
|-------------|--------|-------------|
| `opportunist` | — | Offer one item. If mismatch → leave visit. Match → sell |
| `desperate` | — | Offer all items until sale or customer storms off |
| `highest_offer` | `min_value` (default 10) | Skip items below value threshold. Offer rest aggressively |
| `faction_loyalist` | `faction` (e.g. "syndicate") | Only sell to specified faction. Send away other customers |
| `hoarder` | — | Never enter market. Accumulate shed items |

### Profile assignment at simulation start

```
--profile YAML_FILE                   Custom profile definitions (default content/bots.yml)
--profile-weights "a=3,b=1"          Weighted distribution. Only named profiles are included.
                                      Each bot gets a random profile from the weighted pool.
                                      Without --profile-weights, profiles cycle round-robin.
```

---

## 5. `content/text/crier.yml`

Daily maintenance messages. One message per day, chosen by priority.

```yaml
crier_messages:
  faction_surge:                           # Priority 4 — faction gained influence
    - "{faction} is on a tear — {influence_gain} value in artifacts..."
  faction_slump:                           # Priority 2 — faction had no gain
    - "A {faction} caravan was quiet..."
  faction_dominance:                       # Priority 5 — new faction leader
    - "{faction} now commands the Bazaar..."
  milestone:                              # Priority 3 — N artifacts received
    - "{faction} just received their {count}th artifact..."
  season_opening:                          # Priority 1 — day 1 only
    - "A new season dawns..."
  daily_progress:                          # Priority 0.5 — day-range fallback
    - day_max_pct: 0.10                    #   (or day_min/day_max for absolute days)
      messages:
        - "The season is young..."
    - day_min_pct: 0.10
      day_max_pct: 0.33
      messages:
        - "The Bazaar is finding its rhythm..."
    - "<unbucketed messages>"              #   Catch-all if no bucket matches
  generic:                                 # Priority 0 — last resort
    - "The mountain looms..."
```

### Message priority (higher wins)

| Category | Priority |
|----------|----------|
| `faction_dominance` | 5 |
| `faction_surge` | 4 |
| `milestone` | 3 |
| `faction_slump` | 2 |
| `season_opening` | 1 |
| `daily_progress` | 0.5 |
| `generic` | 0 |

### Bucket types for `daily_progress`

| Field | Type | Description |
|-------|------|-------------|
| `day_min` | integer | Absolute minimum season day (inclusive) |
| `day_max` | integer | Absolute maximum season day (inclusive) |
| `day_min_pct` | float 0–1 | Proportional minimum: checks `day/length >= this` |
| `day_max_pct` | float 0–1 | Proportional maximum: checks `day/length <= this` |

Absolute fields (`day_min`, `day_max`) take priority over proportional
(`day_min_pct`, `day_max_pct`). Messages without any threshold act as
catch-all fallbacks.

---

## 6. `content/text/negotiation_reactions.yml`

Per-faction flavor text for market visit outcomes. Replaces hardcoded
generic messages when text exists for a faction.

```yaml
negotiation_reactions:
  syndicate:                              # Faction ID (must match factions.yml)
    match:                                # Offer was a match (auto-sale)
      - "The Syndicate buyer offers {value} scrap."
    settle:                               # Mismatch settled by random roll
      - "Fine. {value} scrap."
    mismatch:                             # Mismatch, no settle
      - "Not what we're looking for."
    storm_off:                            # Irritation exceeded threshold
      - "We're done here."
```

### Template variables

| Variable | Replaced with |
|----------|---------------|
| `{value}` | The offer amount in scrap |
| `{item_id}` | The artifact's ID string |

Any faction can omit any outcome. Missing outcomes fall back to generic
sprintf messages in the code.

---

## 7. `content/text/commission_triggers.yml`

Narrative text for faction commission events. Currently content-only —
the Commission System (§7.3 of GAME_ARCHITECTURE.md) is not yet implemented.

```yaml
commission_triggers:
  syndicate:
    - "A runner from the Syndicate finds you at camp..."
```

### Template variables

| Variable | Replaced with |
|----------|---------------|
| `{faction}` | Faction name |
| `{behavior}` | Behavior tag (e.g. "thermal") |

---

---

## Tuning Principles

### Risk vs Reward

The core tension is **push vs collapse**. Every artifact parameter should be
evaluated against this tradeoff:

- **Higher `base_value` / `base_gain`** → more reward per push → players push
  more aggressively → more collapses → more excitement. If average score per
  bot rises above ~250 in a 14-day sim, either values are too high or collapse
  is too rare.
- **Higher `max_instability` / lower `instability_growth`** → slower risk
  accumulation → more pushes before collapse → higher final values. Extends
  the "safe zone."
- **Lower `evolution_threshold` / higher `evolution_chance`** → breakthroughs
  feel attainable. If breakthroughs happen on >15% of artifacts, the mechanic
  becomes expected rather than exciting.

### Faction Balance

`base_multiplier` should be inversely related to how many artifacts match
a faction's interests:

- Syndicate (1.1, 4 interests) — moderate pay, broad coverage
- Purifiers (1.2, 3 interests) — best pay, narrow coverage
- Revelationists (0.8, 4 interests) — worst pay, broad coverage

If one faction dominates simulation scores, either its `interests` are too
common or its `base_multiplier` is too high relative to coverage.

### The Standing Loop

Standing compounds: more sales → higher standing → better prices (+0.05×
per point) + more frequent customers (+0.5 weight per point). This means
high-volume sellers (desperate, highest_offer) naturally pull away from
low-volume sellers (opportunist, loyalist) over longer seasons.

If opportunist or loyalist scores trail badly in extended sims (14+ days),
the issue may not be the sell policy — it could be the standing feedback
loop amplifying volume advantages. Consider narrowing the standing effect
(change +0.05 to +0.03) or widening faction interests to help selective
sellers find matches.

### Signal Text Tuning

Signal text has no mechanical effect. Guidelines for writing good signals:

- **Stable**: Curiosity and wonder. Describe the artifact's state neutrally.
- **Strained**: Warning signs. Temperature, sound, vibration changes.
- **Unstable**: Urgency and danger. Sensory overload, visible distress.
- **Collapse**: Finality. The artifact is gone. Should feel consequential.

Avoid game-rule language ("instability is increasing"). Use concrete
sensory detail ("the casing warps"). See `docs/Tone Guide.md`.

---

## Quick Start Guides

### Adding a New Artifact — Quick Start

1. Add a new entry to `content/prospecting.yml`
2. Give it a unique `id` starting from `_001`
3. Assign `behaviors` that match at least one faction's `interests`
4. Copy decay_modifiers from an existing artifact (or omit for defaults)
5. Write at least 2 signals per stage and 1 collapse text
6. Run `prove -l t/` to verify no breakage
7. The new artifact will appear in the draw pool automatically

## Adding a New Faction — Quick Start

1. Add a new entry to `content/factions.yml`
2. Choose `interests` that overlap with existing artifact behaviors
3. Add at least one bot profile to `content/bots.yml` if you want it tested
4. Add `negotiation_reactions` entries for flavor text
5. No code changes needed

## Editing a Bot Profile — Quick Start

1. Edit the profile in `content/bots.yml`
2. Change `push_policy.name` to any policy from the table above
3. Change `sell_policy.name` and `params` to any policy from the table above
4. Test with: `perl -Ilib script/mountain simulate --count 5 --days 14 --profile-weights "your_profile_id=5"`
5. Analyze with: `perl -Ilib script/analyze_sim <transcript>`
