# Multi-Item Market Visit V2 — Implementation Plan

## Goal

Replace the current basic multi-item system (irritation-carries-over) with a
budget-pressure system that makes Market Visits a true push-your-luck loop.

---

## Design Summary

Each customer has a **soft budget** (`soft_budget`) and tracks
`spent_so_far` across all sales in the visit. Sales that push
`spent_so_far` over `soft_budget` increase irritation. Sales under budget
do not irritate — they feel clean.

A sale within 5% of the customer's absolute budget (hard limit, see below)
awards a **precision bonus** — extra scrap for reading the customer well.

Standing with the faction raises the soft budget, rewarding loyalists with
longer, more lucrative visits.

---

## Customer State

New fields on the customer hashref:

```perl
$customer = {
    # Existing fields...
    faction_id          => 'syndicate',
    desired_behaviors   => ['thermal', 'power'],
    irritation          => 0,
    irritation_threshold => 5,
    base_multiplier     => 1.1,
    settle_chance       => 0.15,

    # New fields
    soft_budget          => 100,   # generated at visit start
    absolute_budget      => 120,   # hard cap (soft × 1.2)
    spent_so_far         => 0,     # cumulative sale value in this visit
    budget_pressure      => 0.0,   # 0..1 ratio: spent_so_far / soft_budget
};
```

### Budget Generation

```perl
# On begin():
my $base_budget = 50 + int(rand(100));              # 50–150 base
my $standing_bonus = ($standing->{$faction->{id}} // 0) * 5;  # +5 per standing
$customer->{soft_budget}     = $base_budget + $standing_bonus;
$customer->{absolute_budget} = int($customer->{soft_budget} * 1.2);
```

The absolute budget is 1.2× soft. Going over soft ticks irritation. Going
over absolute triggers an immediate storm-off (the customer literally can't
afford it).

### Budget Pressure States

Derived from `spent_so_far / soft_budget`, returned in view for the UI:

| Ratio | State | Narrative signal |
|-------|-------|-----------------|
| 0.00–0.50 | comfortable | "The buyer eyes your wares eagerly." |
| 0.51–0.80 | interested | "The buyer checks their funds thoughtfully." |
| 0.81–1.00 | wary | "The buyer hesitates, calculating." |
| 1.01–1.10 | strained | "The buyer is stretching thin." |
| 1.11–1.19 | leaving soon | "The buyer glances toward the exit." |
| 1.20+ | over absolute | "The buyer cannot afford another item." |

---

## Irritation Sources

| Event | Irritation | Notes |
|-------|:----------:|-------|
| Match sale (under soft budget) | **+0** | Clean sale |
| Match sale (over soft budget) | +1 | Over budget strains patience |
| Match sale (close to absolute) | **bonus** | Within 5% of absolute = precision bonus |
| Counter-offer accepted (under budget) | +1 | Haggled sale |
| Counter-offer accepted (over budget) | +1 | Over-budget replaces haggle (not +2) |
| Lowball settle | +1 | Forced compromise |
| Mismatch (no settle, no counter) | +1 | Wrong item |
| Counter-offer rejected (offer another) | +1 | Wasted time |
| Over absolute rejection | +2 | Customer can't afford it |
| Storm off | 0 | Customer leaves, visit over |

### Precision Bonus

If the sale pushes `spent_so_far` to within 5% of `absolute_budget` (but
strictly less than 100%), the player gets a bonus. The bonus is added to
the sale value (what the player receives as scrap/score) but does NOT count
toward `spent_so_far` — it is free value on top, not additional budget
pressure. An exact hit on absolute_budget does NOT trigger the bonus.

```perl
# Order: 1) spent_so_far is already incremented by offer_value (pre-bonus)
#        2) check if spent_so_far / absolute_budget is in 95-99.99% range
#        3) bonus is added to the player's payout, NOT to spent_so_far
my $pct_of_abs = $customer->{spent_so_far} / $customer->{absolute_budget};
if ($pct_of_abs >= 0.95 && $pct_of_abs < 1.0) {
    my $bonus = int($offer_value * 0.15);   # 15% bonus
    $offer_value += $bonus;
}
```

This rewards players who can estimate how much a customer can spend.

---

## Standing Grants

| Sale type | Standing delta |
|-----------|:-------------:|
| Match (under budget) | +2 |
| Match (over budget) | +1 |
| Counter accepted | +1 |
| Lowball settle | +0 |
| Over absolute (rejected — no sale) | N/A |

---

## Customer Mood Feedback (Must-Have)

The UI must communicate budget pressure without exposing raw numbers.

### Pressure States

Each state has a faction-specific reaction pool in
`content/text/negotiation_reactions.yml`. New keys per faction:

```yaml
negotiation_reactions:
  syndicate:
    match:
      - "..."
    settle:
      - "..."
    mismatch:
      - "..."
    storm_off:
      - "..."
    counter:
      - "..."
    # New pressure feedback keys:
    mood_comfortable:
      - "The Syndicate buyer eagerly eyes your next item."
    mood_interested:
      - "The buyer nods, still listening."
    mood_wary:
      - "The buyer checks their coin purse."
    mood_strained:
      - "The buyer winces as you name your price."
    mood_leaving:
      - "The buyer's hand drifts toward the exit."
    precision_bonus:
      - "You hit {value} scrap on the nose. Impressive."
    over_absolute:
      - "The buyer shakes their head. 'I simply don't have that kind of scrap.'"
```

Template variables: `{value}`, `{item_id}`, `{faction_name}`.

Mood feedback fires after each sale, on the `sold_more` view result. The
view includes a `pressure_state` string field and a `budget_pressure_pct`
numeric field (for bot consumption):

```perl
return {
    view => {
        ok                 => 1,
        result             => 'sold_more',
        value              => $value,
        pressure_state     => 'mood_strained',
        budget_pressure_pct => $customer->{spent_so_far} / $customer->{soft_budget},
        irritation         => $customer->{irritation},
        max_irritation     => $customer->{irritation_threshold},
        message            => $narrative,
        player             => $self->_player_snapshot($char),
    },
};
```

---

## Over Absolute Budget

If a sale would push `spent_so_far` over `absolute_budget`, the customer
refuses. The offer is rejected with `result => 'over_budget'`, no sale
occurs, and irritation ticks by 2. The customer does not storm off
immediately — the visit continues, but the next offer attempt checks
irritation against threshold as usual (if irritation >= threshold,
storm-off occurs).

If the sale itself *is* within absolute but would go over soft budget,
the sale proceeds with +1 irritation (from over-budget pressure).

---

## Bot Behavior

### New Sell-Policy Params

| Param | Default | Description |
|-------|:-------:|-------------|
| `max_irritation` | 3 | Stop offering when irritation ≥ this |
| `max_budget_pressure` | 1.0 | Stop when budget_pressure ≥ this (1.0 = soft budget) |
| `haggle_aggression` | 0.5 | 0 = never accept counters, 1 = always accept |
| `min_counter_pct` | 0 | Minimum counter value / decayed_value ratio to accept |

### Policy Defaults

| Policy | `max_irritation` | `max_budget_pressure` | `haggle_aggression` | `min_counter_pct` |
|--------|:----------:|:-------------:|:-------------:|:------------:|
| opportunist | 3 | 0.80 | 0.70 | 0.70 |
| desperate | 4 | 1.15 | 0.90 | 0.40 |
| highest_offer | 2 | 0.50 | 0.00 | — |
| faction_loyalist | 3 | 1.00 | 0.80 | 0.60 |

**Opportunist**: Conservative on budget (stop at 80%), picky on counters.
**Desperate**: Push past soft budget, accept almost any counter, high irritation
tolerance.
**Highest_offer**: Leave early (50% budget, 2 irritation), never haggle.
**Faction_loyalist**: Match budget to soft, accept most counters, moderate
irritation tolerance.

### Bot Decision Loop

```perl
while ($keep_offering) {
    my $current_items = $shed->find(...);
    for my $item (@$current_items) {
        unless (should_offer_item($char, $item, $pol)) { next }

        my $view = $activity->offer(...);

        if ($view->{result} eq 'sold' || $view->{result} eq 'sold_more') {
            # Check budget pressure
            if ($view->{budget_pressure_pct} >= $max_budget_pressure) {
                $activity->send_away($char);
                $keep_offering = 0;
            } elsif ($view->{irritation} >= $max_irritation) {
                $activity->send_away($char);
                $keep_offering = 0;
            }
            if ($view->{result} eq 'sold') { last }
            last;  # sold_more: re-query shed
        }
        if ($view->{result} eq 'counter_offer') {
            if (haggle_aggression check) { accept }
            else { try_another or stop }
        }
        if ($view->{result} eq 'over_budget') {
            # Try a cheaper item — customer can't afford this one
            next;
        }
        # no_match, customer_left, etc.
    }
}
```

---

## Config Toggles

The `market_multi_item` flag remains (single toggle). Its behavior changes
from the basic irritation-carries-over system to this budget-pressure system.
Counter-offers remain gated by `market_counter_offers` (separate toggle).

Budget pressure is computed on **every** visit, even single-item mode.
The precision bonus can fire on a single sale. This ensures consistent
mechanics regardless of toggle state.

Both default to 0 (disabled). The default behavior is still single-item
visits with no counter-offers, but budget fields are always present on
the customer hashref.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Activity/MarketVisit.pm` | Replace basic multi-item with budget-pressure system. Add `soft_budget`, `absolute_budget`, `spent_so_far`, `budget_pressure` to customer. Implement irritation from over-budget, precision bonus, over-absolute rejection. Add `pressure_state` to view results. |
| `lib/MagicMountain.pm` | Add config keys for budget defaults if needed (soft_budget_min, soft_budget_max, absolute_multiplier, precision_bonus_pct). |
| `lib/MagicMountain/Command/simulate.pm` | Bot loop uses `max_budget_pressure`, `haggle_aggression` params. |
| `lib/MagicMountain/Bot/SellPolicy.pm` | Add `should_haggle` dispatch table. |
| `content/bots.yml` | Rename `accept_counter` → `haggle_aggression` in profiles. Add `max_budget_pressure`. |
| `content/text/negotiation_reactions.yml` | Add mood feedback keys per faction. |
| `GAME_ARCHITECTURE.md` | Update §6.5 with budget-pressure mechanics. Add `sold_more` view contract with `pressure_state`. Update standing table. Update §13.1 endpoint contracts. Remove "planned enhancements" note. |
| `FUTURES.md` | Already marked as DONE. Update description to mention budget pressure. |
| `docs/content_reference.md` | Update bots.yml sell policies table with `max_budget_pressure`, `haggle_aggression`. Add faction YAML fields if any (none needed — budget is generated, not configured). |
| `t/market_visit.t` | Update tests for budget-pressure multi-item. Test precision bonus, over-budget rejection, standing → budget effect. |
| `t/market_visit_web.t` | Web integration tests for `sold_more` with pressure state. |
| `t/bot_simulate.t` | Simulate tests with new bot params. |

---

## Metrics to Track

New fields logged in `sale` and `sold_more` transcript events:

- `spent_so_far` / `soft_budget` (budget_pressure ratio)
- `sale_type` (match / counter / settle)
- `over_budget` boolean
- `precision_bonus` boolean + value

Aligned analysis:

| Metric | Source |
|--------|--------|
| Sales per market visit | transcript `sale` events grouped by visit |
| Items sold per visit | count sales before `customer_left` or `send_away` |
| Score per market AP | sum of sale values per visit |
| Budget pressure at visit end | `spent_so_far / soft_budget` of last sale |
| Precision bonus rate | `precision_bonus` flags / total sales |
| Over-budget rate | `over_budget` flags / total sales |
| Irritation at visit end | last event's irritation value |
| Standing gained by type | `sale_type` + `standing_delta` from disposition |
| Win rate by sell policy | traditional |
| Median / max score by policy | traditional |

---

## Order of Implementation

1. **Customer budget state** — Add soft_budget, absolute_budget, spent_so_far
   generation in `begin()`. Add budget_pressure computation.
2. **Irritation from over-budget** — Modify `_do_sale` to check spent_so_far
   vs soft_budget, tick irritation if over. Over-absolute rejection.
3. **Precision bonus** — Check spent_so_far vs absolute_budget after sale,
   apply 15% bonus if within 5%.
4. **Mood feedback** — Add pressure_state to `sold_more` view. Add reaction
   keys to negotiation_reactions.yml. Wire `_pick_reaction` for mood keys.
5. **Bot params** — Add `max_budget_pressure`, `haggle_aggression` to
   SellPolicy.pm and bots.yml. Update sim bot loop.
6. **Doc sync** — GAME_ARCHITECTURE.md §6.5, FUTURES.md, content_reference.md.
7. **Tests** — Unit tests for budget generation, precision bonus, over-budget
   rejection, over-soft irritation. Web tests for mood feedback. Bot sim test
   with new params.
