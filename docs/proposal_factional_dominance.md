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

## Design Constraints

All proposals below stay within these boundaries:

- No touch to push/collapse physics (per §17 #13). Affecting an artifact's
  starting instability is permitted — that sets initial position on the curve,
  not the curve itself.
- No deterministic rules (per "On Factions").
- No faction membership (per "On Factions").
- No dominance-weight on customer frequency — the dominant faction should not
  appear more often, but the customers who do arrive should feel different.
- No effective skill bonuses. Players invest scrap into skills; climate should
  not cheapen that investment.
- All expressed through the economic/opportunity layer.

---

## Architecture: Daily Faction Climate

Faction climate is calculated once per day during daily maintenance, after bots
have acted and faction influence totals have updated. This gives every player on
the same day a consistent, predictable world state.

Daily flow:

```
daily maintenance starts
bots take actions
faction influence totals update
calculate faction climate for the coming day
store climate on Season
generate town crier notice from climate
daily maintenance ends
```

Prospecting and MarketVisit read the stored climate for the current day. They
never recalculate or recompute dominance themselves.

### Climate Data Shape

Stored as a JSON column on `season`:

```perl
{
  day => 12,
  dominant_faction => 'syndicate',
  intensity => 'strong',           # contested | leading | strong | dominant
  dominance_margin => 17,          # influence delta between leader and runner-up

  prospecting => {
    draw_biases => {               # weight multipliers by behavior
      thermal => 1.3,
      storage => 1.2,
      power   => 1.1,
      force   => 0.75,
    },
    starting_instability_mod => 1, # added to artifact starting_instability
  },

  market => {
    budget_delta => 2,             # added to customer budget range (centiles)
    mood_delta => -1,              # added to customer starting mood
    patience_delta => -1,          # added to customer patience
    risk_tolerance_delta => 1,     # added to customer risk tolerance
    buyer_trait_biases => {        # extra demand weight for these trait sales
      volatile => 1,
      luxury => 1,
    },
  },

  town_crier => {
    headline => 'The Roads Belong to Fast Money',
    body => 'The Syndicate\'s runners were seen outside the east gate...',
    hint => 'Expect richer customers, sharper tempers, and less stable finds.',
  },
}
```

### Season Accessor

```perl
sub faction_climate ($self) { $self->getCol('faction_climate') }
```

Return an empty/neutral hashref if no climate is stored (first day of season,
contested leader, or legacy data).

---

## Dominance Intensity Tiers

Do not treat faction dominance as merely "winner exists." The strength of the
lead should scale the magnitude of all modifiers.

| Margin | Tier | Modifier scale |
|--------|------|----------------|
| 0–4 | Contested | No climate effect (neutral day) |
| 5–12 | Leading | 1× (base modifiers) |
| 13–24 | Strong | 1.5× (modifiers amplified) |
| 25+ | Dominant | 2× (modifiers at maximum) |

Thresholds subject to tuning. The tier determines the intensity label shown
in the UI and the multiplier applied to all climate modifier values.

---

## A. Dominance-Skewed Draw Pool

When a faction is dominant, artifacts whose `behaviors` align with that
faction's `interests` get a **draw-weight bonus** proportional to the dominance
lead. Artifacts that conflict get a **draw-weight penalty**.

Faction-specific trait profiles:

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

**Implementation sketch**: In `Prospecting::_draw_artifact`, read
`season.faction_climate.prospecting.draw_biases`. For each artifact spec,
multiply its `weight` by the bias for each of its `behaviors`. If no bias
entry exists, weight is unchanged. No new columns, no new models.

---

## B. Dominant Faction Saturation Floor

Currently, trait saturation applies equally to all factions regardless of
position. Change: the dominant faction **ignores saturation for its own
preferred trait** — their demand is effectively insatiable for that one thing.
Their multiplier never drops below `base_multiplier` for their top interest.

No scarcity penalty for rival factions. The dominant faction's special status
is a pull (always worth selling to them for that one trait), not a push
(penalizing sales elsewhere).

**Player-choice impact**: Selling the dominant faction's preferred trait is
always profitable, no diminishing returns. The player chooses between the
reliable dominant-faction sale and potentially higher but more volatile prices
from rivals.

**Constraint-safe**: Market economics only. No push changes.

**Implementation sketch**: In `_dynamic_multiplier`, if the current faction is
the influence leader and the artifact's primary behavior matches the faction's
first `interests` entry, apply a saturation floor of `base_multiplier`.

---

## C. Starting Instability Modifier

The dominant faction's influence on the Mountain changes the baseline stress
level of artifacts recovered that day.

| Intensity | Modifier |
|-----------|----------|
| Contested | 0 |
| Leading | +1 starting instability for artifacts matching the dominant faction's less-common traits |
| Strong | +1 starting instability for all drawn artifacts |
| Dominant | +2 starting instability for all drawn artifacts |

This does not change the collapse formula, `instability_growth_min/max`,
`max_instability`, or any push mechanic. It shifts the artifact's starting
position on an unchanged curve.

**Player-choice impact**: Artifacts enter the push cycle closer to the
strained threshold. The player must decide whether to push fewer times (safe,
lower value) or accept the elevated collapse risk from a higher starting
position.

**Legibility**: "The Mountain feels dangerous today. Artifacts come out of the
ground already restless."

**Constraint-safe**: Starting instability is an artifact initial-condition
parameter, not a push mechanic. Collapse probability per push is unchanged.

**Implementation sketch**: In `Prospecting::_apply_defaults`, add
`climate.prospecting.starting_instability_mod` to the artifact's
`starting_instability` after defaults are applied.

---

## D. Multi-Axis Buyer Climate

Old approach: the dominant faction appeared more often (frequency). New
approach: the dominant faction's buyers are **different when they arrive** —
they have budgets, moods, patience, and risk tolerance shaped by that day's
climate.

| Climate axis | What it affects | Code location |
|---|---|---|
| `budget_delta` | Customer's budget range (added to base budget roll) | `MarketVisit::begin`, customer generation |
| `mood_delta` | Customer's starting mood in negotiation | `MarketVisit::begin` |
| `patience_delta` | Customer's irritation threshold | `MarketVisit::begin` |
| `risk_tolerance_delta` | Customer's willingness to buy unstable/dangerous artifacts | `MarketVisit::offer`, match logic |
| `buyer_trait_biases` | Extra demand-weight for listed traits (overrides standing-based price multiplier) | `MarketVisit::_weighted_faction` (price calc, not frequency) |

Customer faction frequency remains purely standing-weighted (`1.0 + 0.5 ×
standing`). Climate modifies the customer struct after selection, not the
selection weights.

The `mood_delta` and `patience_delta` axes are gated: they only apply when the
customer's faction matches `dominant_faction`. `budget_delta` and
`risk_tolerance_delta` apply to all customers on a climate day — the
dominant faction's influence shifts the entire market.

**Player-choice impact**: The dominant faction's buyers are richer and
pushier, but dealing with them affects standing with their rivals. You can seek
them out or avoid them — but the market overall is tighter, looser, or stranger
based on who's in charge.

**Constraint-safe**: Customer generation and price match only. No push
changes.

**Implementation sketch**: In `MarketVisit::begin`, after the customer faction
is selected, apply climate modifiers to the customer struct. In
`_dynamic_multiplier`, add `buyer_trait_biases` as weighting factors alongside
existing trait-matching logic.

---

## E. Dominance-Gated Commissions

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
  draw pool (due to A).
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

## UI: Today's Climate Card

A compact display on the home dashboard, rendered from the stored climate
object:

```
Today's Climate: Syndicate — Strong
Finds:  more thermal/storage gear, less volatile
         Artifacts start slightly more stressed
Market: richer buyers, shorter tempers
```

The climate card is informational only. No actions live on it. It updates once
per day after the player's first dashboard load following maintenance.

---

## Town Crier Integration

The town crier receives the climate object as its authoritative source for the
daily faction-dominance message. The message structure:

```
Headline       — e.g. "The Roads Belong to Fast Money"
Flavor body    — in-universe description of the shift
Practical hint — what the player should expect in gameplay terms
```

The Crier's existing `faction_dominance` priority level (5, highest) maps
directly to climate days. On contested days, the Crier falls through to
lower-priority messages.

---

## Summary: Why These Together

| Component | What the player feels | Choice it creates |
|---|---|---|
| Skewed draw pool | "All I am finding is Purifier-friendly gear." | Sell to Purifiers or hold out for rarer rival-bait |
| Saturation floor | "The Syndicate never gets tired of power artifacts." | Keep feeding the dominant faction or chase rival prices |
| Starting instability mod | "The Mountain feels dangerous today." | Push conservatively or accept the elevated starting risk |
| Buyer climate | "Syndicate buyers are loaded and rude today." | Engage the dominant faction's buyers or sell to calmer rivals |
| Commission gating | "LibreMount is offering 1.9× if I bring them a heater." | Chase the premium (help the underdog) or take the easy dominant-faction sale |

The through-line: **You can play *with* the dominance trend or *against* it,
but you cannot ignore it.** Every choice has a visible cost-benefit tied to
which faction is winning the race and how far ahead they are.

---

## Implementation Order

1. **Daily climate calculation and storage** — New method in daily maintenance
   controller. JSON column on Season. New service `Dominance.pm` for all
   calculation logic. No consumer changes.

2. **Buyer climate (D)** — Apply stored modifiers to customer struct in
   `MarketVisit::begin`. No schema changes.

3. **Skewed draw pool (A)** — Read `draw_biases` in `Prospecting::_draw_artifact`.
   No schema changes.

4. **Saturation floor (B)** — One conditional in `_dynamic_multiplier`.
   No schema changes.

5. **Starting instability modifier (C)** — Add `starting_instability_mod` in
   `Prospecting::_apply_defaults`. No schema changes.

6. **Commission gating (E)** — Depends on the Commission System (§7.3) being
   implemented first. The dominance gating is then layered on top of the
   existing commission trigger.

7. **Climate card + Crier** — Template and Crier generator changes.
   Depends on step 1.

## Scoring Criteria

| Criteria | A (Draw) | B (Saturation) | C (Instability) | D (Buyers) | E (Commissions) |
|---|---|---|---|---|---|
| Player-visible | Medium (indirect) | Medium (indirect) | High (before every push) | High ("rich and rude") | High ("LibreMount wants one") |
| Choice pressure | Medium | Low-Medium | Medium | Medium | High |
| Implementation effort | 1-2 hrs | 1 hr | 1 hr | 1-2 hrs | 3-4 hrs (needs commissions) |
| Risk of feel-bad | Low (probabilistic) | Low | Medium (extra collapse risk from start) | Low | Low |
