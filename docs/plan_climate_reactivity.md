# Plan: Climate Reactivity & Artifact Identity

## Context

The climate system already computes buyer_trait_biases and applies them as
match_mult bonuses in MarketVisit — but the player cannot see artifact traits,
cannot see what the climate prizes, and never senses the reactivity.

The player has no reason to care what artifacts they keep, because no artifact
has visible identity beyond its value.

**Design constraint**: Make the existing system visible and felt. No new
activities, no new persistence tables, no maintenance hooks. The premium
already exists — make it legible.

## Review Sign-off

- [x] Architecture review complete
- [x] Implementation review complete

## Steps

### Step 1: Surface artifact traits in the salvage ledger

**Goal**: Players can distinguish artifacts by identity (thermal, volatile,
signal) not just by value.

**Tests**: t/shed_web.t — render shed fragment, assert behavior tags appear.

**Implementation**:
- Controller/Shed.pm _enriched_items: add computed field
  `tags => join(', ', @{$behaviors})`.
- templates/components/salvage_ledger.html.ep: add a trait tags cell between
  the Item cell and the Value cell. The column order is:
  Item | Tags | Value | [Action if market_active]
  Style the tags as small amber badges (inline spans with mm-text-amber).
  An example row cell: `<span class="mm-text-amber" style="font-size:0.7rem">
  volatile, luxury</span>`

**Verify**: prove t/shed_web.t

### Step 2: Show climate-preferred traits on the climate card

**Goal**: Players see "Paying premium for: volatile, luxury" on the home
dashboard when a faction is dominant.

**Tests**: t/home_web.t — set up dominant faction climate with
buyer_trait_biases, assert the card renders the trait list.

**Implementation**:
- templates/components/climate_card.html.ep: after the market_summary line,
  add a line listing buyer_trait_biases keys when present. Format:
  `<div class="mm-text-amber">Paying premium for: volatile, luxury</div>`
  Guard with `if ($cc->{market}{buyer_trait_biases})`.

**Verify**: prove t/home_web.t

### Step 3: Show desired behaviors in the negotiation panel

**Goal**: When the player visits market, they see what the customer is
looking for, connecting shed contents to match odds.

**Tests**: t/market_visit_web.t — call begin, assert "Seeking: ..." text in
the negotiation fragment.

**Implementation**:
- MagicMountain/Customer.pm: add `desired_behaviors` to the `has` list.
  Update TO_JSON to include `desired_behaviors`.
- Controller/Market.pm show(): pass desired_behaviors and climate_trait_biases
  through to the template. The raw customer hash is already available
  (`$c = $activity->customer`). These fields are already on the hash.
  Include them when constructing the Customer object.
- templates/market/negotiation.html.ep: after the disposition line, add:
  `<p class="mm-text-dim" style="font-size:0.78rem">Seeking:
  <%= join(', ', @{ $customer->desired_behaviors // [] }) %></p>`
- Activity/MarketVisit.pm begin handler (in the view hash return, around
  original line 315-327): remove `revealed_behavior` from the customer view
  hash. The `$revealed` variable and the conditional at line 296-298 can be
  deleted entirely since desired_behaviors are now always visible.
  Instead of removing the entire 296-298 block, remove just the
  `revealed_behavior` wiring: the `$revealed` variable assignment and its
  conditional inclusion in the view hash. The $sell variable is still needed
  elsewhere (line 390 for match_mult).

**Note**: The `$revealed` removal is part of this step, NOT Step 7. Step 7
handles the budget-range *addition* at the same location.

**Also update**: t/market_visit.t — replace the existing check for
`revealed_behavior` in the begin response (around lines 333-334) with
a check that desired_behaviors is present in the view (since we show all
now unconditionally).

**Verify**: prove t/market_visit_web.t, prove t/market_visit.t

### Step 4: Surface climate premium in the offer response

**Goal**: When a sale benefits from a buyer_trait_bias, the player sees
"Climate premium: +30%".

**Tests**: t/market_visit.t — after a match offer with climate_trait_biases
active, assert the sale result includes climate_premium_pct.

**Implementation**:
- Activity/MarketVisit.pm offer handler (in the match branch where
  climate_trait_biases is applied, around original line 390-395): after
  computing the match_mult adjustments from climate_trait_biases, compute
  `climate_premium_pct` as the percentage increase contributed by climate
  biases. For example, if base match_mult was 1.2 and biases multiplied it
  by 1.3, the premium_pct is 30.
  Store on the customer struct: `$customer->{climate_premium_pct}`.
- Activity/MarketVisit.pm _do_sale: in the `last_sale` hash (set on the
  customer struct), include `climate_premium_pct` from the customer struct.
  Also include it in both return view hashes (single-sale path and
  multi-item path).
- templates/market/negotiation.html.ep: when `$customer->last_sale` has
  `climate_premium_pct`, show a green badge in the sale result area:
  `<span class="mm-badge mm-badge-green">+<%= $customer->last_sale->{climate_premium_pct} %>%
  climate premium</span>`

**Verify**: prove t/market_visit.t, prove t/market_visit_web.t

### Step 5: Skew desired_behaviors toward climate-biased traits

**Goal**: When a climate is active, customers from the dominant faction
desire the climate-biased traits, making the climate feel reactive rather
than algebraic.

**Tests**: t/market_visit.t — mock climate with specific biases, call
begin, assert desired_behaviors includes biased traits. Also test that
duplicate traits between climate biases and faction interests are deduped.

**Implementation**:
- Activity/MarketVisit.pm _pick_behaviors: accept an optional second
  parameter $climate_biases (hashref). When present, build the initial pool
  by taking keys of $climate_biases plus the faction's interests, then
  deduplicate via List::Util::uniq (or manual dedup). Then pick the random
  count (1-3) from this combined pool without replacement. The biased traits
  should appear in the pool with at least equal weight to interests.
  Simplified approach: seed the pool with biased trait keys, then fill to
  the target count (1-3) by appending randomly-selected interests.
  Use `List::Util::uniq` to deduplicate.
- In the begin handler, pass `$customer->{climate_trait_biases}` as the
  second argument to _pick_behaviors when it exists.

**Verify**: prove t/market_visit.t

### Step 6: Climate-aware home dashboard suggestion

**Goal**: When the dominant faction pays a premium for traits the player
has in their shed, the home dashboard suggests visiting the Bazaar.

**Tests**: t/home_web.t — set up climate + shed with matching item, assert
suggestion text contains faction name and trait. Update any existing tests
that mock Suggestion::build() to pass the new parameter.

**Implementation**:
- Service/Suggestion.pm build(): change the signature from
  `($char, $season, $advisories, $shed_count)` to
  `($char, $season, $advisories, $all_shed)` where $all_shed is an
  arrayref of shed item hashes (each with `getCol('behaviors')` access).
  Update the existing `$shed_count` usage to `scalar @$all_shed`.
  Then check: for each biased trait key in
  `$season->faction_climate.market.buyer_trait_biases`, check if any
  shed item's behaviors include it. If so, push a suggestion.
- Controller/Home.pm show(): change the call from
  `$self->app->suggestion->build($char, $season, $advisories, $shed_count)`
  to pass `$all_shed` instead of `$shed_count`. The controller already
  loads shed items for the ledger, so pass that arrayref.
- content/flavor/advisories.yml: add `climate_match` entry:
  "{faction} paying premium for {traits} in your shed — visit Bazaar."
  Document the interpolation variables: {faction} = faction display name,
  {traits} = comma-separated trait names.

**Verify**: prove t/home_web.t

### Step 7: Replace Selling skill 3 effect — budget range

**Goal**: Skill 3 still has value after desired_behaviors become visible.
Replace the old reveal-one-behavior with showing the customer's budget
range.

**Tests**: t/market_visit.t — assert that when sell >= 3, the begin
response and the negotiation fragment include budget_min and budget_max.
t/market_visit_web.t — assert budget range text appears in fragment.

**Implementation**:
- Activity/MarketVisit.pm begin handler: at the location where the
  `$revealed` variable was removed (Step 3), add a new block:
  ```perl
  my $budget_range = ($sell >= 3) ? {
      budget_min => $customer->{soft_budget},
      budget_max => $customer->{absolute_budget},
  } : undef;
  ```
  Include in the view hash:
  ```perl
  (defined $budget_range ? (budget => $budget_range) : ()),
  ```
- MagicMountain/Customer.pm: add `budget_min` and `budget_max` as optional
  has attributes. Update TO_JSON to include them.
- Controller/Market.pm show(): read `$char_model->getCol('skill_selling')`,
  conditionally add budget fields to the Customer constructor:
  ```perl
  my $sell = $char_model->getCol('skill_selling') // 0;
  my %budget;
  if ($sell >= 3 && $c) {
      %budget = (budget_min => $c->{soft_budget}, budget_max => $c->{absolute_budget});
  }
  ```
- templates/market/negotiation.html.ep: when `$customer->budget_min` is
  set, show "Budget range: 80–96 scrap" after the seeking line.
- content/skills.yml: update UP-CEL level 3 description: "persuasion
  algorithm — reveals buyer budget range"
- GAME_ARCHITECTURE.md: update UP-CEL table (line 1070):
  "3 | Customer budget range revealed; match multiplier increased from
   1.2x to 1.4x base_multiplier"
  Also update the earlier reference at line 2177-2178 to remove
  `revealed_behavior` and reflect the new budget-range mechanic.

**Verify**: prove t/market_visit.t, prove t/market_visit_web.t

### Step 8: Walkthrough update

**Goal**: Walkthrough exercises the new visibility paths.

**Implementation**:
- bin/walkthrough: after visiting shed, assert tags appear in fragment.
  After climate shift in crier, assert climate card shows premium traits.
  After market begin, assert desired behaviors and budget range appear.

**Verify**: perl bin/walkthrough

## Selling Skill 3 — Final Effect Table

| Level | Old Effect | New Effect |
|-------|-----------|------------|
| 1 | Estimate range narrowed +-20% to +-15% | Unchanged |
| 2 | Irritation gain on mismatches eliminated | Unchanged |
| 3 | +0.2 match_mult; reveals one desired_behavior | +0.2 match_mult (1.4x); reveals budget range |

## Open Questions

1. **Show desired_behaviors unconditionally?** Yes — seeing what factions
   want is core gameplay info, not a skill gate. The climate already makes
   faction preferences semi-public (crier messages), so showing them in the
   negotiation panel is consistent with the fiction.

2. **Climate premium annotation in the shed ledger?** A future nice-to-have,
   not in scope for this pass. The climate card and dashboard suggestion
   provide enough connection.

3. **Should the skewed desired_behaviors include traits from buyer_trait_biases
   that aren't in the faction's interest list?** Yes — Syndicate's buyer_trait_
   biases are `{volatile, luxury}` which don't appear in their `interests:
   [thermal, storage, food_processing, power]`. The climate adds new desires.

4. **Test coverage threshold?** Existing t/market_visit.t, t/home_web.t,
   t/shed_web.t, t/market_visit_web.t are the test beds. No new test files.

## Completion Checklist

- [ ] Shed ledger shows trait tags per artifact (Step 1)
- [ ] Climate card shows premium traits (Step 2)
- [ ] desired_behaviors added to Customer.pm has list + TO_JSON (Step 3)
- [ ] Negotiation panel shows desired behaviors (Step 3)
- [ ] revealed_behavior removed from begin handler view hash (Step 3)
- [ ] Old revealed_behavior test assertion updated (Step 3)
- [ ] Offer response shows climate premium % (Step 4)
- [ ] climate_premium_pct in last_sale hash + _do_sale return views (Step 4)
- [ ] Customer desired_behaviors skewed by climate, deduped (Step 5)
- [ ] Suggestion::build() signature updated to accept all_shed (Step 6)
- [ ] Home controller passes all_shed instead of shed_count (Step 6)
- [ ] Home dashboard suggests climate-matched sales (Step 6)
- [ ] advisories.yml climate_match entry added (Step 6)
- [ ] Selling skill 3 shows budget range in begin view hash (Step 7)
- [ ] Budget range surfaced in Customer.pm and Market.pm show() (Step 7)
- [ ] Negotiation panel shows budget range (Step 7)
- [ ] GAME_ARCHITECTURE.md UP-CEL table + revealed_behavior refs updated (Step 7)
- [ ] content/skills.yml level 3 description updated (Step 7)
- [ ] Walkthrough updated (Step 8)
- [ ] No regression on prove t
- [ ] Old plan files removed (plan_climate_visibility.md, plan_reactive_shed.md)
