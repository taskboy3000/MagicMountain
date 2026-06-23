# Market Visit Enhancements — Implementation Plan

## Goal

Extend the single-offer MarketVisit flow with two layered mechanics:

1. **Multi-item sales**: After a match-sale, the customer stays — keep selling
   until irritation ends the visit or you send them away.
2. **Counter-offers (haggle step)**: On mismatch (when settle fails), the
   customer counters at a midpoint price. Accept at that value or reject
   (irritation +1, try another).

Both are gated by app-config flags so simulations can toggle them on/off.

---

## Rationale

The current implementation is one-shot: match → sale → visit over. This
flattens the market phase into a binary "sell or don't" with no tension past
the first offer. Multi-item sales + counter-offers turn the market visit into
a press-your-luck mini-game: each additional item risks irritation, and each
counter-offer tests your willingness to compromise.

This matches the design intent in §6.5, which explicitly mentions showing
another artifact and the irritation/storm-off mechanic as the visit's
tension arc.

---

## Design

### Multi-Item Sales

**Flow change**: `offer` → match → `_do_sale` → **customer asks "anything
else?"** → repeat

Changes to `_do_sale()`:
- Record sale, delete shed item, update standing/faction_state (as today)
- **Skip** `$self->delete` and `pending_activity_id` clear
- Reset `pending_counter` to undef (no pending haggle)
- Return view result `sold_more` instead of `sold`
- Include `irritation` and `irritation_threshold` in the `sold_more` view
  so the bot (and UI) can decide whether to continue offering

The customer hashref persists — its `irritation` counter carries over
across rounds.

**Standing grants by sale type** — reduced standing for compromised
sales to prevent the feedback loop from amplifying volume:
- Match sale: +2 standing (unchanged)
- Accepted counter: +1 standing
- Lowball settle (random settle hit on mismatch): **+0 standing**

This means `_do_sale` needs a sale-type parameter beyond the current
`$was_match` boolean — a tri-state or enum (`match`, `counter`, `settle`).

**Irritation does NOT reset on sale**. This is the press-your-luck mechanism:
each mismatch ticks irritation up by 1. A single sale does not reset the
counter. The player must read the customer's reactions (irritation level)
to decide whether to push their luck or walk away with what they have.

If irritation exceeds the threshold on a subsequent mismatch, the customer
storms off — same `customer_left` result as today, and the visit ends.

**When does the visit end?**
- Player sends the customer away (`send_away`) — always available
- Customer storms off (irritation ≥ threshold) — failure
- Player presses their luck one too many times

**Bot behavior**:
- New param `max_irritation` on sell-policy profiles (default 3)
- Bot stops offering when `irritation >= max_irritation` and returns
  to the `send_away` path (or the existing `try_another` logic)
- **Bot loop restructure**: The current `for my $item (@$shed_items)` loop
  in the simulation bot may reference stale (already-deleted) items after a
  sale. Under multi-item, the bot must reload shed items after each sale
  and restructure into a `while` loop that re-queries the shed. The loop
  also needs to check `$activity->customer->{irritation}` against
  `max_irritation` after each `sold_more` to decide whether to keep going.

---

### Counter-Offers (Haggle Step)

**Flow change**: `offer` → mismatch → settle roll fails → **counter at
midpoint** → accept (sale) or reject (irritation +1, try another)

**Transition table update**: Add `accept_counter` to the `negotiating`
phase actions: `{ idle => ['begin'], negotiating => ['offer', 'send_away', 'accept_counter'] }`

The mismatch path currently goes straight to irritation + "try another".
With counter-offers enabled, the flow is:

1. No intersection → lowball at `decayed × dyn_mult × 0.5`
2. Settle roll — if it hits, sale at lowball (same as today)
3. Settle fails → **customer counters** at `decayed × dyn_mult × 0.75`
   - Selling skill 2+ → counter at `0.80×`
   - Standing bonus stacks additively: +0.01 per standing point to the
     midpoint factor. With sell 2+ and standing 10: `0.80 + 0.10 = 0.90×`
   - `_apply_loyalty_bonus` does **not** apply to counter-offer values
     (the counter is already a compromise)
4. Returns view result `counter_offer` with the counter value
5. Player action `accept_counter` → `_do_sale` at counter price
   - If player offers the **same** item that has a pending counter,
     it auto-accepts (treated as `accept_counter`)
6. Player shows a different item → implicit rejection, irritation +1,
   try another

**Important**: When counter-offers are enabled, the `offer` handler's
mismatch path must defer the irritation increment. In the current code,
irritation is incremented immediately after settle fails (before return).
Under counter-offers, this block becomes: if offers enabled → create
pending_counter + return `counter_offer` (no irritation yet); if offers
disabled → existing behavior (irritation + `no_match`).

**State**: Customer hashref gains a `pending_counter` field:

```perl
$customer->{pending_counter} = {
    value => $counter_value,
    item_id => $shed_item_id,
};
```

If the player offers a different item, the pending counter is cleared
(implicit rejection). If the player sends away, the counter is discarded.

**Bot behavior**:
- New param `accept_counter` on sell-policy profiles (default 1 = always accept)
- New param `min_counter_pct` for pickier policies — only accept if
  counter ≥ `decayed × min_counter_pct` (e.g. 0.70 means "only accept
  70%+ of decayed value")
- `highest_offer` policy sets `accept_counter: 0` (never accept a
  counter — wait for a match or try another faction)
- `desperate` policy sets `accept_counter: 1` (gratefully accept)
- `opportunist` policy accepts if standing is good, rejects if they
  think they can do better

---

## Config Toggles

### App config (`magic_mountain.yml` or `defaultConfig`)

```yaml
market_counter_offers: 0    # disabled by default
market_multi_item: 0        # disabled by default
```

### Simulate CLI flags

```
perl -Ilib script/mountain simulate --count 10 --days 30 --counter-offers --multi-item
```

Two new flags:
- `--counter-offers` → sets `market_counter_offers: 1`
- `--multi-item` → sets `market_multi_item: 1`

Sim command feeds these into `app->config` before running.

### Bot profile params

Each existing profile in `content/bots.yml` gains a `params` block with
the new fields. Profiles that already have a `params` block (e.g.
`fixed_highest` with `min_value`) get the new fields merged in.

Defaults for any profile that lacks these params:
- `max_irritation`: 3
- `accept_counter`: 1 (accepts counters)
- `min_counter_pct`: 0 (accept any counter)

Expected per-profile values (to be tuned during sim validation):

| Profile ID | `max_irritation` | `accept_counter` | `min_counter_pct` | Notes |
|---|---|---|---|---|
| `stage_guard_opportunist` | 3 | 1 | 0.70 | Default opportunist |
| `fixed_highest` | 2 | 0 | — | Never takes a counter, leaves early |
| `desperate` | 4 | 1 | 0.50 | Pushes irritation, accepts most counters |
| `fixed_loyalist` | 3 | 1 | 0.60 | Accepts counters |
| `stage_loyalist` | 3 | 1 | 0.65 | Slightly pickier |
| `greed_loyalist` | 3 | 1 | 0.70 | Accepts only good counters |
| `value_loyalist` | 2 | 0 | — | Never takes a counter (like highest_offer) |

---

## Files Changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Activity/MarketVisit.pm` | Multi-item exit path in `_do_sale`, counter-offer flow in `offer` handler, new `accept_counter` handler, pending_counter state, update transition table |
| `lib/MagicMountain/Controller/Market.pm` | Add `accept_counter` action dispatching to activity |
| `lib/MagicMountain.pm` | Add `market_counter_offers` and `market_multi_item` to `defaultConfig` |
| `lib/MagicMountain/Command/simulate.pm` | Add `--counter-offers` and `--multi-item` flags, set config keys before run |
| `lib/MagicMountain/Bot/SellPolicy.pm` | Add `max_irritation`, `accept_counter`, `min_counter_pct` evaluation in bot offer loop |
| `content/bots.yml` | Add new params to existing profiles |
| `GAME_ARCHITECTURE.md` | Update §6.5 to reflect multi-item and counter-offer mechanics. Add `POST /market/accept_counter` to §13.1 endpoint table. Mark §6.5 MarketVisit Enhancements as implemented. |
| `FUTURES.md` | Move "MarketVisit Enhancements (§6.5)" from Defer to Done. Update Desperate Recruiter sub-item under Market Dynamics if scope changes. |
| `t/market_visit.t` | Update tests for multi-item + counter-offer paths |
| `t/market_visit_web.t` | Web integration tests for new actions |
| `t/bot_simulate.t` | Simulate tests with new config flags |

---

## Bot Strategy Impact

The new params create real differentiation in how bots navigate the market:

| Policy | `max_irritation` | `accept_counter` | `min_counter_pct` | Behavior |
|--------|:---:|:---:|:---:|---|
| opportunist | 3 | 1 | 0.70 | Sell 1-2 items, accept good counters |
| highest_offer | 2 | 0 | — | Never take a counter, leave early |
| desperate | 4 | 1 | 0.50 | Push irritation, accept most counters |
| loyalist | 3 | 1 | 0.60 | Accept counters for their faction |
| hoarder | — | — | — | Skips market entirely (unchanged) |

---

## Order of Implementation

1. **Multi-item sales** — simpler change: modify `_do_sale` exit path,
   add `sold_more` result, update bot loop. No new activity action needed.
2. **Counter-offers** — new action `accept_counter`, haggle flow in
   `offer` handler, pending_counter state, transition table update.
   Requires deferred-irritation restructuring in the mismatch path.
3. **Bot profile params + simulate flags** — wire everything up.
4. **Architecture + Futures doc sync** — update §6.5 in
   GAME_ARCHITECTURE.md, mark MarketVisit Enhancements as Done in
   FUTURES.md.
5. **Tests** — existing tests pass with flags off (default), new tests
   exercise each flag combination.

**Testing phases** (run 20-seed / 30-day sims, each with a single toggle
or pair, **in this order**):
1. Counter-offers only (`--counter-offers`): safer change, expected to
   improve floor and add texture without exploding AP efficiency.
2. Multi-item only (`--multi-item`): isolates AP-efficiency impact
   (this is the riskier change — 1 AP can now liquidate multiple items).
3. Both together (`--counter-offers --multi-item`): full intended
   experience.

Do not judge the combined system first. The combined system changes
both sale conversion rate and AP efficiency simultaneously. The
testing order follows the feature toggles, not the implementation
order — both features exist in code before any testing begins.

---

## Resolved Decisions

- **Standing + sell skill stacking**: Both stack additively. Sell 2+
  gives `0.80×` base; standing adds `+0.01/point`.
- **Loyalty bonus on counters**: No. The counter is already a
  compromise price.
- **Same-item re-offer with pending counter**: Auto-accept — treat as
  `accept_counter`.
- **Bot profile params**: Added inline to existing `content/bots.yml`
  profiles.
- **`send_away` mid-visit**: Yes — player can always walk away with
  what they've earned.
- **AP cost**: 1 AP covers the whole visit. Irritation is the cost
  of multiple offers.
- **Counter-negotiation**: Not in scope. Player accepts or rejects
  the single counter.

---

## Metrics to Track in Simulation Reports

Existing score/win-rate tables are insufficient. Add:

| Metric | Why |
|--------|-----|
| Market visits per bot | Baseline visit rate |
| Sales per market visit | Measures multi-item throughput |
| Counter-offers generated | How often haggling fires |
| Counters accepted | Acceptance rate by policy |
| Match sales vs counter sales vs lowball settles | Sale-type distribution |
| Average value by sale type | Does accepting counters pay less? |
| Standing gained by sale type | Are compromised sales still feeding the loop? |
| Irritation at visit end | Are bots pressing too hard? |
| Customer storm-off rate | How often does irritation cap hit? |
| Items remaining in shed at season end | Inventory liquidation rate |
| **Score per market AP** | **Most important metric** — measures AP-efficiency change |
