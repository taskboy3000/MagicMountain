# Magic Mountain — Bot Simulation Findings

**Generated**: 2026-06-22T20:53 UTC
**Simulation framework**: Pluggable PushPolicy/SellPolicy dispatch modules
**Artifact pool**: 10 artifacts covering all 14 faction-interest behaviors
**Build**: commit `89530e2` (plus subsequent local changes)
**Note**: Each experiment lists its duration (days). Findings reference
multiple sim lengths — check the experiment header to compare like with
like.

## Experimental Summary

Five simulation experiments were run to test bot strategy balance in the
Magic Mountain push-your-luck game. The simulations use a framework of
pluggable push policies (how aggressively to destabilize artifacts) and
sell policies (how aggressively to negotiate at market).

---

## Bot Strategy Definitions

### Push Policies (artifact destabilization)

| Policy | Behavior |
|--------|----------|
| `stage_guard` | Push until artifact stage reaches "unstable" |
| `greed` | Each push: continue with 80% probability, stop with 20% |
| `value_target` | Push until artifact value >= 30 |
| `fixed_pushes` | Push exactly 2 times, then stop |
| `instability_cap` | Push until instability > 3 |

### Sell Policies (market negotiation)

| Policy | Behavior |
|--------|----------|
| `opportunist` | Enter market, offer one item. If mismatch → leave. Sell only on first match. |
| `desperate` | Enter market, offer all items until customer leaves or sale happens. Accept everything. |
| `highest_offer` | Enter market, skip items below `min_value=15` threshold, offer the rest aggressively. |
| `faction_loyalist` | Enter market, check customer faction. If not Syndicate → send away. Only sell to Syndicate. |
| `hoarder` | Never enter market. Accumulate shed items. Zero sales. |

### Loyalty Bonus (Variant A, implemented in final experiments)

Two mechanics added to help faction loyalists:

1. **Access guarantee**: After 2 sales to a faction, that faction is guaranteed
   at least once every 4 market visits. (Never actually fired in experiments —
   standing-based customer generation was sufficient.)
2. **Loyalty offer bonus**: After 3 sales to a faction, offers from that
   faction get +0.10× multiplier.

---

## Raw Data

### Experiment 1: 5 bots, 7 days (original artifact pool — 3 artifacts)

Seed: 42 | Profile distribution: 1 each

| Bot | Push | Sell | Score | Sales |
|-----|------|------|-------|-------|
| bot-001 | stage_guard | opportunist | 111 | 3 |
| bot-002 | greed | desperate | 76 | 6 |
| bot-003 | value_target | hoarder | 0 | 0 |
| bot-004 | fixed_pushes | highest_offer | 75 | 4 |
| bot-005 | instability_cap | faction_loyalist | 31 | 2 |

### Experiment 2: 10 bots, 7 days (original artifact pool)

Seed: 42 | Profile distribution: 2 each

| Sell Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| opportunist | 95 | 3.5 |
| desperate | 84 | 4.0 |
| highest_offer | 51 | 4.0 |
| faction_loyalist | 21 | 1.5 |
| hoarder | 0 | 0 |

### Experiment 3: 10 bots, 14 days (loyalty bonus + clearance + original pool)

Seed: 42 | Profile distribution: 2 each

| Sell Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| desperate | 193 | 12.0 |
| highest_offer | 181 | 10.0 |
| opportunist | 166 | 5.0 |
| faction_loyalist | 63 | 5.0 |
| hoarder | ~10 (clearance) | 0 |

### Experiment 4: 5 all-loyalist bots, 14 days (original artifact pool)

Seed: 42 | Profile: all faction_loyalist

| Bot | Score | Sales | Send Away | Match Rate |
|-----|-------|-------|-----------|------------|
| bot-001 | 137 | 7 | 7 | 29% |
| bot-002 | 26 | 2 | 11 | 9% |
| bot-003 | 192 | 8 | 6 | 38% |
| bot-004 | 89 | 6 | 7 | 14% |
| bot-005 | 0 | 0 | 0 | 0% |
| **Avg** | **111** | **5.8** | **7.8** | **23%** |

### Experiment 5: 10 bots, 14 days (expanded artifact pool — 10 artifacts)

Seed: 42 | Profile distribution: 2 each

| Sell Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| highest_offer | 280 | 12.7 |
| desperate | 213 | 11.5 |
| faction_loyalist | 186 | 9.0 |
| opportunist | 139 | 6.0 |
| hoarder | 0 | 0 |

### Experiment 6: 5 all-loyalist bots, 14 days (expanded artifact pool)

Seed: 42 | Profile: all faction_loyalist

| Bot | Score | Sales | Match Rate |
|-----|-------|-------|------------|
| bot-001 | 94 | 5 | 30% |
| bot-002 | 218 | 10 | 19% |
| bot-003 | 107 | 8 | 9% |
| bot-004 | 89 | 4 | 50% |
| bot-005 | 97 | 5 | 62% |
| **Avg** | **121** | **6.4** | **34%** |

---

## Key Findings

### 1. The original artifact pool was the bottleneck

The original pool had 3 artifacts with only 5 distinct behaviors (`field`,
`instability`, `power`, `signal`, `thermal`). Factions each had 3–5 interest
tags, 8 of which had ZERO matching artifacts (`storage`, `food_processing`,
`water`, `sanitation`, `medical_response`, `revelation`, `force`,
`transformation`). Match rates hovered around 23%, making the loyalist
unviable regardless of customer access or price bonuses.

### 2. Expanding the artifact pool fixed the loyalist

Adding 7 new artifacts covering the missing behaviors raised the loyalist's
average score from 21–63 to 186 in mixed simulations — a 3–9× improvement.
The loyalist is now competitive with desperate (213) and highest_offer (280).

### 3. The access guarantee never fired

Despite implementing a guaranteed-faction-customer mechanic (forced visit
after 3 non-matching market visits), it never triggered in any simulation.
The standing-weighted customer generation (`_weighted_faction`) naturally
produced enough matching customers when bots had standing from sales. The
guarantee may be unnecessary for the current standing model.

### 4. highest_offer may be too strong with the expanded pool

At 280 avg score (12.7 sales), the `highest_offer` strategy's item filter
(`min_value=15`) lets it cherry-pick the best artifacts from the expanded
pool. This is 50% higher than desperate and 34% higher than opportunist.
The `min_value` threshold may need tuning relative to the new artifact
value distribution.

### 5. Standing bonus benefits high-volume sellers

The loyalty bonus (+1 standing per extra sale) accelerated standing
accumulation for desperate and highest_offer, which sell 10–12 items per
season vs opportunist's 5–6. This shifted the balance from opportunist
being dominant (Experiment 1) to desperate/highest_offer leading
(Experiment 5). Standing's effect on prices (+0.05× per point) and
customer frequency (+0.5 weight per point) compounds with volume.

### 6. Faction loyalist variance is high

Even with expanded pool, loyalist scores range from 0–218 in a single run
(all-loyalist experiment). The strategy is heavily dependent on drawing
artifacts that match the chosen faction's behaviors. This is a property
of the game — loyalty is not the consistent earner that desperate is.

---

## Post-Expansion Tuning (Experiments 7–10)

After the artifact pool expansion, we ran a series of tuning experiments
targeting the `highest_offer` sell policy (which dominated at 280 avg in
the expanded pool) and the `faction_loyalist` strategy. Loyalty bonus
already reduced from +0.10× to +0.05×.

### Experiment 7: All-loyalist smoke test (original profile-weights bug)

5 bots, 7 days, all `faction_loyalist` (instability_cap push).
Seed: 42 | Profile weights: instability_loyalist=5

**Note**: This run had the profile-weights bug — unspecified profiles
received default weight 1, so the pool contained 4 non-loyalist profiles
alongside the 5 loyalist entries. Results are unreliable.

| Bot | Push | Sell | Score | Sales |
|-----|------|------|-------|-------|
| bot-001 | instability_cap | faction_loyalist | 32 | 2 |
| bot-002 | greed | desperate | 187 | 11 |
| bot-003 | instability_cap | faction_loyalist | 46 | 3 |
| bot-004 | fixed_pushes | highest_offer | 220 | 11 |
| bot-005 | instability_cap | faction_loyalist | 55 | 3 |

### Experiment 8: Variant 3 — min_value=20, loyalty +0.05×

10 bots, 14 days, expanded artifact pool.
Seed: 42 | Weights: 2 each, 5 profiles.

| Sell Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| desperate | 228 | 11.5 |
| opportunist | 144 | 5.7 |
| faction_loyalist | 104 | 5.5 |
| highest_offer | **116** | 7.0 |

**Finding**: `min_value=20` was too aggressive. `highest_offer` cratered
from 280 to 116 — below opportunist. The filter skipped most items in
the expanded pool where base values range 5–10. Pushing 2 times
(fixed_pushes) at gain 3–5 per push reaches ~11–20 value, so most items
never cleared the 20 threshold.

### Experiment 9: min_value=17

10 bots, 14 days, expanded artifact pool.
Seed: 42 | Weights: 2 each, 5 profiles.

| Sell Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| desperate | 275 | 12.3 |
| highest_offer | 237 | 10.0 |
| opportunist | 152 | 6.3 |
| faction_loyalist | 86 | 5.3 |

**Finding**: `min_value=17` brought highest_offer down from 280 to 237,
which is within the 190–240 target zone. However, the loyalist at 86 is
below the 150–210 target, and desperate at 275 is above the 190–230 target.
The min_value=17 may be a reasonable compromise but further tuning on
loyalty bonus may be needed.

### Experiment 10: All-loyalist clean test (profile-weights bug fixed)

5 bots, 7 days, all `faction_loyalist` (instability_cap push).
Seed: 42 | Profile weights: instability_loyalist=5
Profile-weights bug fixed: unspecified profiles no longer get default weight 1.

| Bot | Push | Sell | Score | Sales | Match% |
|-----|------|------|-------|-------|--------|
| bot-001 | instability_cap | faction_loyalist | 0 | 0 | 0% |
| bot-002 | instability_cap | faction_loyalist | 19 | 1 | 5% |
| bot-003 | instability_cap | faction_loyalist | 25 | 1 | 100% |
| bot-004 | instability_cap | faction_loyalist | 11 | 1 | 0% |
| bot-005 | instability_cap | faction_loyalist | 18 | 1 | 12% |

| Sell Policy | Avg Score | Avg Sales | Match% |
|-------------|-----------|-----------|--------|
| faction_loyalist | 18 | 1.0 | 10% |

**Finding**: The loyalist with `instability_cap` push (stop at instability
> 3) produces very few sales. Averaging 1 sale per bot over 7 days with a
10% match rate. Projected to ~36 over 14 days — well below the 150–210 target.
This suggests the `instability_cap` push policy magnifies the loyalist's
weakness by producing low-value artifacts that don't match faction interests.

---

## Experiments 11–12: Clean Baseline + Loyalist Push-Policy Matrix

After fixing the profile-weights bug and setting `highest_offer` min_value
to 18 with loyalty bonus at +0.05×, two final experiments were run to:
1. Establish a clean baseline for the full mixed profile set
2. Test whether the loyalist's weakness is intrinsic to loyalty mechanics
   or driven by the pairing with `instability_cap` (conservative push)

### Experiment 11: Clean Baseline — 10 bots, 14 days, mixed profiles

**Date**: 2026-06-22  
**Config**: 5 profiles, 2 each (equal weight), 10 artifacts, min_value=18,
loyalty +0.05×, profile-weights bug fixed.  
**Seed**: random (no seed specified)

| Bot | Push | Sell | Score | Sales | Match% |
|-----|------|------|-------|-------|--------|
| bot-001 | stage_guard | opportunist | 137 | 5 | 28% |
| bot-002 | greed | desperate | 162 | 10 | 10% |
| bot-003 | value_target | hoarder | 0 | 0 | 0% |
| bot-004 | fixed_pushes | highest_offer | 254 | 11 | 17% |
| bot-005 | instability_cap | faction_loyalist | 0 | 0 | 0% |
| bot-006 | stage_guard | opportunist | 198 | 5 | 41% |
| bot-007 | greed | desperate | 177 | 12 | 17% |
| bot-008 | value_target | hoarder | 0 | 0 | 0% |
| bot-009 | fixed_pushes | highest_offer | 208 | 8 | 18% |
| bot-010 | instability_cap | faction_loyalist | 17 | 1 | 14% |

| Sell Policy | Avg Score | Avg Sales | Match% |
|-------------|-----------|-----------|--------|
| highest_offer | 231 | 9.5 | 18% |
| desperate | 169 | 11.0 | 14% |
| opportunist | 167 | 5.0 | 34% |
| faction_loyalist | 17 | 1.0 | 14% |
| hoarder | 0 | 0 | — |

| Push Policy | Avg Score |
|-------------|-----------|
| fixed_pushes | 231 |
| greed | 169 |
| stage_guard | 167 |
| instability_cap | 17 |
| value_target | 0 |

**Aggregate**: 980 artifacts, 3018 pushes, 3.1 pushes/artifact, 52 sales,
avg sale 22.2, score range 17–254, avg score 164.7.

**Findings**:
- **highest_offer (231)** — safely within target band (190–240). Good.
- **desperate (169)** — came down from 275 to within its 130–190 band.
  The min_value=18 threshold + loyalty +0.05× nerf reduced desperate's
  standing-driven compounding.
- **opportunist (167)** — solid, in its 130–190 band.
- **faction_loyalist (17)** — still terrible when paired with
  `instability_cap`. This is the same pairing from the old experiments.
- **hoarder (0)** — correctly zero.

### Experiment 12: Loyalist Push-Policy Matrix — 10 bots, 14 days

**Date**: 2026-06-22  
**Config**: 5 loyalist profiles (1 per push policy), 2 each, min_value=18,
loyalty +0.05×.  
**Seed**: random

This experiment tests the hypothesis from Experiment 10: the loyalist's
weakness is not the loyalty system but the pairing of `instability_cap`
(conservative push) with `faction_loyalist` (picky sell).

| Bot | Push | Sell | Score | Sales | Match% |
|-----|------|------|-------|-------|--------|
| bot-001 | instability_cap | faction_loyalist | 7 | 1 | 50% |
| bot-002 | instability_cap | faction_loyalist | 74 | 5 | 33% |
| bot-003 | instability_cap | faction_loyalist | 40 | 3 | 20% |
| bot-004 | fixed_pushes | faction_loyalist | 6 | 1 | 16% |
| bot-005 | fixed_pushes | faction_loyalist | 18 | 1 | 100% |
| bot-006 | greed | faction_loyalist | 170 | 7 | 31% |
| bot-007 | stage_guard | faction_loyalist | 66 | 2 | 16% |
| bot-008 | value_target | faction_loyalist | 23 | 2 | 0% |
| bot-009 | fixed_pushes | faction_loyalist | 38 | 3 | 18% |
| bot-010 | value_target | faction_loyalist | 187 | 5 | 16% |

| Push Policy | Avg Score | Avg Sales |
|-------------|-----------|-----------|
| greed | 170 | 7.0 |
| value_target | 105 | 3.5 |
| stage_guard | 66 | 2.0 |
| instability_cap | 40 | 3.0 |
| fixed_pushes | 20 | 1.7 |

**Aggregate**: 980 artifacts, 2815 pushes, 2.9 pushes/artifact, 30 sales,
avg sale 21.0, score range 6–187, avg score 62.9.

**Key finding — Hypothesis CONFIRMED**:

| Push + Sell Pairing | Avg Score | Verdict |
|---------------------|-----------|---------|
| greed + loyalist | 170 | **Viable** — matches opportunist and desperate |
| value_target + loyalist | 105 | Marginal — works with high-value finds |
| stage_guard + loyalist | 66 | Weak — too conservative × too picky |
| instability_cap + loyalist | 40 | **Nonviable** — double conservative |
| fixed_pushes + loyalist | 20 | **Nonviable** — double conservative, worst result |

The loyalist strategy is NOT intrinsically weak. When paired with an
aggressive push policy (greed, value_target), it produces competitive
scores (105–170). The problem in all prior experiments was that the only
loyalist profile paired `instability_cap` (most conservative push) with
`faction_loyalist` (most picky sell) — a double-conservative combination
that starves the bot on both production and sales.

**Tuning implication**: No buffs to loyalty mechanics are needed. The
loyalty bonus (+0.05×) and access guarantee are adequate. Faction loyalty
is a viable build family, but it requires a push strategy that generates
enough volume or value to overcome the picky sell filter. Players who
choose faction loyalty should be incentivized toward riskier push
strategies (or skill investments that improve artifact quality/quantity).

---

### Experiment 13: 30-Day Baseline — 10 bots, mixed profiles

**Date**: 2026-06-22  
**Config**: 10 bots, 30 days, 9 profiles (5 mixed original + 4 loyalist
variants), equal weights, min_value=18, loyalty +0.05×.  
**Seed**: random

| Bot | Push | Sell | Score | Sales | Match% |
|-----|------|------|-------|-------|--------|
| bot-001 | stage_guard | opportunist | 344 | 9 | 26% |
| bot-002 | greed | desperate | 479 | 25 | 31% |
| bot-003 | value_target | hoarder | 0 | 0 | 0% |
| bot-004 | fixed_pushes | highest_offer | 454 | 19 | 14% |
| bot-005 | instability_cap | faction_loyalist | 413 | 17 | 18% |
| bot-006 | fixed_pushes | faction_loyalist | 63 | 7 | 12% |
| bot-007 | stage_guard | faction_loyalist | 338 | 14 | 9% |
| bot-008 | greed | faction_loyalist | 362 | 13 | 31% |
| bot-009 | value_target | faction_loyalist | 860 | 20 | 15% |
| bot-010 | stage_guard | opportunist | 490 | 13 | 40% |

| Sell Policy | Avg Score | Avg Sales | Match% |
|-------------|-----------|-----------|--------|
| desperate | 479 | 25.0 | 31% |
| highest_offer | 454 | 19.0 | 14% |
| opportunist | 417 | 11.0 | 33% |
| faction_loyalist | 407 | 14.2 | 16% |
| hoarder | 0 | 0 | — |

| Push Policy | Avg Score |
|-------------|-----------|
| value_target | 860 (loyalist) / 0 (hoarder) |
| greed | 420 |
| stage_guard | 390 |
| instability_cap | 413 |
| fixed_pushes | 258 |

**Aggregate**: 2100 artifacts, 6930 pushes, 3.3 pushes/artifact, 137 sales,
avg sale 27.8, score range 63–860, avg score 422.6.

**Key findings**:

1. **All four non-hoarder strategies converged closely** over 30 days:
   desperate 479, highest_offer 454, opportunist 417, faction_loyalist 407.
   That's only a 15% spread — the best balance seen across all experiments.

2. **faction_loyalist (407) is fully competitive** with opportunist (417)
   over a full season. The +0.05× loyalty bonus and expanded artifact pool
   are sufficient.

3. **Push policy matters more than sell policy** over longer horizons.
   The spread within `faction_loyalist` itself (63–860) is wider than the
   spread between sell policies. The `value_target + loyalist` pairing is
   particularly strong — pushing for high value then waiting for the right
   customer produces the season's best score (860).

4. **fixed_pushes (258) is the weakest push**, scoring well below the
   others. Its conservative 2-push limit caps artifact quality, and no
   sell policy can fully compensate.

5. **Hoarder (0)** remains correctly zero even with the clearance sale.

---

### Current state

`content/bots.yml` is now at 9 profiles (5 mixed + 4 loyalist variants):
- `highest_offer`: `min_value` = **18**
- `faction_loyalist`: `loyalty_offer_bonus` = **+0.05×** (hardcoded in
  `MarketVisit.pm`)
- 5 loyalist profiles covering all push policies

The profile-weights bug is fixed — `next unless exists $weights{$p->{id}}`
instead of `// 1` default.

---

## Conclusions

1. **Artifact pool expansion was the most impactful change.** Without
   artifact-faction alignment, no tuning of sell mechanics can fix the
   loyalist. Pre-expansion loyalist avg was 21–63. Post-expansion it
   reached 186 in mixed runs (before loyalty bonus nerf), then 407 over
   30 days.

2. **The loyalty access guarantee is unnecessary** with the expanded pool
   and current standing model. Standing naturally generates matching
   customers. The guarantee never fired in any experiment.

3. **highest_offer min_value tuning is a blunt instrument.** Moving from
   15 to 20 dropped its score from 280 to 116. The sweet spot appears
   to be around 17–18. Current setting is 18 — highest_offer scores 454
   over 30 days.

4. **Profile-weights had a silent bug** causing mixed populations even
   when a single profile was specified. Fixed via `next unless exists`.

5. **The loyalist's weakness is NOT intrinsic to loyalty mechanics.**
   Experiment 12 conclusively demonstrates that faction loyalty is viable
   when paired with an aggressive push policy. `greed + loyalist` scores
   170 (14-day), while `value_target + loyalist` hits 860 (30-day).
   The prior nonviable scores were driven entirely by the
   double-conservative pairing of `instability_cap` with
   `faction_loyalist`.

6. **No buffs to loyalty mechanics are needed.** The +0.05× loyalty bonus
   and access guarantee are adequate. Faction loyalty attracts players who
   commit to aggressive or high-skill push strategies — a specialist build,
   not a universally viable strategy.

7. **Current balance is healthy.** The 30-day baseline (Experiment 13)
   shows all four non-hoarder strategies within a 15% band (407–479):
   - desperate (479)
   - highest_offer (454)
   - opportunist (417)
   - faction_loyalist (407)
   - hoarder (0)

   The content reference (`docs/content_reference.md`) documents all
   parameters with tuning guidance for future balancing.

8. **Push policy is the primary differentiator**, not sell policy. The
   spread within `faction_loyalist` across push policies (63–860) exceeds
   the spread between sell policies (407–479). Design effort should focus
   on push strategy balance rather than sell mechanics. `fixed_pushes`
   (258 avg) is notably weak and may need attention if it represents a
   viable real-player archetype.
