# Sharpening Factional Dominance Effects on Player Choice

## Current State

Faction dominance currently affects:

- **Market pricing** (saturation/appetite/desperation modifiers) — per-faction
  economics, not dominance-linked
- **Crier broadcasts** — narrative only, no mechanical effect
- **Home-dashboard suggestion** — hints to visit hungry factions
- **Loyalty access redirect** — ensures you can sell to your preferred faction
- **Snub influence gain** — +1 influence to all other factions when you send a
  faction away
- **Random event condition** (`any_faction_days_no_buy_gte`) — global events can
  check hunger

The problem: **The player has little reason to care which faction is dominant.**
The dominance race is observable (Crier, Faction view) but doesn't press back on
player decisions. You can ignore it entirely and play identically.

All four proposals below stay within the existing design constraints:

- No touch to push/collapse physics (per §17 #13)
- No deterministic rules (per "On Factions")
- No faction membership (per "On Factions")
- All expressed through the economic/opportunity layer

---

## 1. Dominance Skews the Artifact Draw Pool

When a faction is dominant, artifacts whose `behaviors` align with that
faction's `interests` get a **draw-weight bonus** proportional to the dominance
lead. Artifacts that conflict get a **draw-weight penalty**.

If Purifiers are dominant (interests: `force`, `instability`,
`medical_response`), weapons-like artifacts are drawn more often, and
industrial/thermal artifacts less. If Revelationists are dominant (interests:
`revelation`, `signal`, `field`, `transformation`), signal-producing or unusual
artifacts appear more.

| Dominant Faction | More common | Less common |
|---|---|---|
| Purifiers | force, instability, medical_response | thermal, storage, water |
| Revelationists | revelation, signal, field, transformation | thermal, food_processing, power |
| Syndicate | thermal, storage, food_processing, power | force, instability, revelation |
| Faculty | signal, revelation, field, medical_response | thermal, food_processing, water |
| LibreMount | thermal, water, sanitation, medical_response, power | signal, revelation, force |

**Player-choice impact**: You prospect more of what the dominant faction wants,
making you likelier to sell to them — or you hold out for rarer items to sell
to their rivals, who may pay a premium for opposition.

**Legibility**: "The settlement has changed. Different things are coming out of
the Mountain."

**Constraint-safe**: Does not alter push/collapse. Does not force. It is a
probability shift.

**Implementation sketch**: In `Prospecting::_draw_artifact`, read the influence
leader from `season.faction_state`. For artifacts whose `behaviors` intersect
the dominant faction's `interests`, multiply `weight` by
`(1 + dominance_skew)` where `dominance_skew` = `influence / total_influence`
(capped at, say, 0.5). For conflicting behaviors (interests of the dominant
faction's natural opponent), apply a reciprocal penalty. No new columns, no new
models.

---

## 2. Dominant Faction Floors Its Own Saturation Penalty

Currently, trait saturation applies equally to all factions regardless of
position. Change: the dominant faction **ignores saturation for its own
preferred trait** — their demand is effectively insatiable for that one thing.
Their multiplier never drops below `base_multiplier` for their top interest.

Simultaneously, the dominant faction's **rivals** get a **supply scarcity
penalty**: if the dominant faction has received 10+ of a trait, rival factions
pay less for that trait (it has been "flooded the market" by association).

**Player-choice impact**: Selling the dominant faction's preferred trait is
always profitable, no diminishing returns. But selling *other* traits to rival
factions becomes harder if the dominant faction has cornered that market. The
player must decide: ride the dominant wave or pay the price for going
elsewhere.

**Constraint-safe**: Market economics only. No push changes.

**Implementation sketch**: In `_dynamic_multiplier`, if the current faction is
the influence leader, apply a saturation floor of `base_multiplier` for the
trait matching the faction's first `interests` entry. For all other factions,
apply an additional `scarcity_penalty` = `min(0.25, count * 0.01)` for traits
where the dominant faction's `intake_by_trait[trait] >= 10`.

---

## 3. Dominance-Weighted Customer Generation

Currently, customer selection is standing-weighted (`1.0 + 0.5 × standing`).
Add a **dominance weight**: the dominant faction's customers are `1.5×` more
likely to appear than their standing alone would suggest. Trailing factions
(influence < 10% of leader) have their weight halved.

**Player-choice impact**: The dominant faction is *everywhere*. You see them
constantly. This creates ambient pressure — you can resist them, but it means
more wasted AP if you constantly send them away. The feedback loop is visible:
the more dominant a faction becomes, the more you are forced to interact with
them.

**Constraint-safe**: Customer generation only. No change to math inside the
visit.

**Implementation sketch**: In `_weighted_faction` (MarketVisit::begin), multiply
the weight by `dominance_factor = 1 + (faction_influence / leader_influence)`
for the leader, and by `0.5` for any faction where `influence / leader_influence < 0.10`.

---

## 4. Commission System Gated by Dominance

The Commission System (§7.3 of GAME_ARCHITECTURE.md) is currently planned at
low priority. Sharpen it: the premium a faction offers scales inversely with
how far they trail the leader.

- **Trailing faction commission**: "You have sold to us before. We need more
  like that thermal unit — the Syndicate is cornering that market. If you bring
  us one, we will pay 1.5×." Premium = `1.5 + (1 - influence_ratio) × 0.5`,
  so a faction at 20% of leader gets up to 1.9×.
- **Dominant faction commission**: "We are setting the standard now. Bring us
  something exceptional." Premium is fixed at 1.2× — smaller, but easier to
  fulfill because the dominant faction's favored traits are more common in the
  draw pool (due to #1).
- **Trigger**: `faction_sales[faction_id] >= 2` AND no active commission AND
  faction not already `noticed` (same as §7.3).

**Player-choice impact**: The player can choose to help an underdog (higher
reward, harder to fulfill) or feed the leader (easier to fulfill, lower
premium). This creates the central tension of the dominance race: do you back
the winner or the contender?

**Constraint-safe**: Commission system is already in the architecture. Only the
trigger/premium logic changes.

**Implementation sketch**: Commission premium becomes a function of
`influence / leader_influence`. Trailing factions (< 0.5 ratio) get
`premium_multiplier = 1.5 + (1 - ratio) × 0.5`. Leading factions (>= 0.5
ratio) get a flat 1.2×. The `behaviors` field of the commission draws from the
faction's `interests` list.

---

## Summary: Why These Four Together

| Sharpening | What the player feels | Choice it creates |
|---|---|---|
| Dominance-skewed draws | "All I am finding is Purifier-friendly gear." | Sell to Purifiers or hold out for rarer rival-bait |
| Saturation floor for dominant faction | "The Syndicate never gets tired of power artifacts." | Keep feeding the dominant faction or take a hit selling elsewhere |
| Dominance-weighted customers | "It is always the damn Faculty now." | Send them away (wasting AP) or sell to them (feeding dominance further) |
| Trailing-faction commission premiums | "LibreMount is offering 1.9× if I bring them a heater." | Chase the premium (help the underdog) or take the easy dominant-faction sale |

The through-line: **You can play *with* the dominance trend or *against* it,
but you cannot ignore it.** Every choice has a visible cost-benefit tied to
which faction is winning the race.

---

## Implementation Order

1. **Sharpening #3 (Dominance-weighted customers)** — Smallest change, single
   method in MarketVisit.pm. No new data structures. High leverage for the
   effort.

2. **Sharpening #1 (Skewed draw pool)** — One method in Prospecting.pm. Reads
   existing `faction_state`. No schema changes.

3. **Sharpening #2 (Saturation floor)** — One method in MarketVisit.pm's
   `_dynamic_multiplier`. No schema changes.

4. **Sharpening #4 (Commission gating)** — Depends on the Commission System
   (§7.3) being implemented first. The dominance gating is then layered on top
   of the existing commission trigger.

## Scoring Criteria

| Criteria | #1 (Draw) | #2 (Saturation) | #3 (Customers) | #4 (Commissions) |
|---|---|---|---|---|
| Player-visible | Medium (indirect — you see different artifacts) | Medium (indirect — offers hold up) | High ("it's always them") | High ("LibreMount wants one") |
| Choice pressure | Medium | Low-Medium | High | High |
| Implementation effort | 1-2 hrs | 1 hr | 30 min | 3-4 hrs (needs commissions) |
| Risk of feel-bad | Low (probabilistic) | Low | Medium (too much of one faction) | Low |
