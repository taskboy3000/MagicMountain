# Frontend Gaps Plan

Backend features that exist but lack frontend presentation.

---

## Current State

| Result type | Backend | Frontend handler | Visual |
|-------------|---------|-----------------|--------|
| `sold` | Done | `loadGame()` | Full reload |
| `sold_more` | Done | Inline | Re-renders card + shed |
| `counter_offer` | Done | Inline | Shows accept button |
| `no_match` | Done | Inline | Re-renders card |
| `over_budget` | Done | Inline | Generic re-render |
| `customer_left` | Done | `loadGame()` | Full reload |
| `sent_away` | Done | `loadGame()` | Full reload |

---

## Gap 1: Precision Bonus Display

**API**: `_do_sale` returns `precision_bonus` (integer, >0 when triggered).

**Frontend**: `offerItem` and `acceptCounter` receive `data.precision_bonus` in `sold` and `sold_more` responses but don't display it.

**Fix**: In the inline handler, if `data.precision_bonus > 0`, append a bonus line to the message:

```js
if (data.precision_bonus > 0) {
  G.market_visit.message += ` Precision bonus: +${data.precision_bonus} scrap!`;
}
```

**File**: `public/js/game.js` — `offerItem()` and `acceptCounter()` `sold_more` cases.

---

## Gap 2: Mood / Pressure State Text

**API**: `_do_sale` returns `pressure_state` (e.g. `mood_comfortable`, `mood_wary`, `mood_strained`) and `message` (faction-specific narrative text).

**Frontend**: The `message` text from the response is shown (which already contains faction-specific mood reactions). The `pressure_state` key is not shown.

**Status**: Largely already working — the `message` field carries the derived narrative. No code change needed unless we want a separate mood indicator (icon, color badge).

**Optional enhancement**: Add a colored badge next to irritation showing the mood state (comfortable = green, wary = yellow, strained = orange, leaving = red).

---

## Gap 3: Over-Budget Special Treatment

**API**: `_over_budget` returns `result: 'over_budget'` with `message` and `irritation`.

**Frontend**: `offerItem` handles `over_budget` inline (re-renders the card) but applies no special visual treatment.

**Fix**: In `renderMarketVisit`, check `G.market_visit.over_budget` flag and show an alert-style banner:

```js
const overBudgetBanner = m.over_budget
  ? '<div class="alert alert-warning mt-2 p-2 small">That item exceeded the buyer\'s budget. Try a cheaper one.</div>'
  : '';
```

**File**: `public/js/game.js` — `offerItem()` `over_budget` case + `renderMarketVisit()`.

---

## Gap 4: Settle vs Match Distinction

**API**: `_do_sale` returns `sale_type` in the transcript but the view only has `value` — the frontend doesn't know if the sale was a match or a settle.

**Backend change needed**: Add `sale_type` to the `sold` and `sold_more` views in `_do_sale`. Then the frontend can show text like "Settled!" vs "Match!" in the sale message.

**Files**: `lib/MagicMountain/Activity/MarketVisit.pm` (`_do_sale`), `public/js/game.js`.

---

## Gap 5: Storm-Off / Customer Left Visual

**API**: `offer` returns `result: 'customer_left'` with `message`.

**Frontend**: `offerItem` calls `loadGame()` (full reload). The message is lost on reload because it's not persisted.

**Fix**: Either persist the last message on the activity, or handle `customer_left` inline (show the storm-off message briefly, then reload after a delay).

**Recommended**: Handle inline with a brief flash message, then reload:

```js
case 'customer_left':
  G.market_visit.message = data.message;
  renderActionCard();
  setTimeout(() => loadGame(), 3000);
  break;
```

**File**: `public/js/game.js` — `offerItem()`.

---

## Gap 6: Market Disabled Reason

**Current**: Market button hidden when shed is empty. No explanation shown.

**Fix**: Show a muted text line in the idle card when the player has AP but no items:

```js
const hasItems = (G.shed?.length ?? 0) > 0;
const marketSection = hasItems
  ? '<button class="btn btn-info" id="btn-market">Visit Market (1 AP)</button>'
  : ap >= 1 ? '<p class="text-muted small mb-0">No artifacts in shed to sell.</p>' : '';
```

**File**: `public/js/game.js` — `renderIdle()`.

---

## Priority Order

1. **Gap 6** (market disabled reason) — trivially small, high UX value
2. **Gap 1** (precision bonus) — data already in response, just display it
3. **Gap 5** (storm-off inline) — prevents losing narrative on terminal events
4. **Gap 4** (sale type) — requires backend change but small
5. **Gap 3** (over-budget banner) — small improvement
6. **Gap 2** (mood badge) — purely cosmetic, lowest priority
