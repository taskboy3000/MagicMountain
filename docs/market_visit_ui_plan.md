# MarketVisit UI Wiring Plan

Wire counter-offer and multi-item sale features into the web UI so players
can actually use them when the config flags are enabled.

---

## Current State

| Feature | Backend | Controller | Route | UI | Web Tests |
|---------|---------|-----------|-------|----|-----------|
| Counter-offers (`market_counter_offers`) | Done | Done | Done | **Missing** | Missing |
| Multi-item sales (`market_multi_item`) | Done | Done | Done | Partial | Missing |

---

## Design Principles

- **No internal game state exposed to client**: The frontend receives only
  what it needs to present choices to the player (customer identity, irritation
  level, pending_counter, result messages). Budget numbers, thresholds, and
  percentages remain server-side to prevent web-developer cheating.
- **Inline API response handling**: `offerItem()` and `acceptCounter()` read
  the API response, display the result message inline, update local
  `G.market_visit`/`G.player` from the response, and re-render the action
  card without a full `loadGame()`. A full `loadGame()` is only called for
  terminal results (`sent_away`, `customer_left`, `sold` in single-item mode).
- **Follow existing patterns**: Mirror `pushArtifact()`'s pattern of reading
  response data and updating state directly rather than always reloading.

---

## Changes

### 1. Expose `pending_counter` in game state endpoint

**File**: `lib/MagicMountain/Controller/Game.pm` (line 100-112)

The JSON response for market_visit currently omits `pending_counter` from the
customer object. The UI needs this to know when a counter-offer is available
after a full page reload.

**Before**:
```perl
$market_view = {
    customer => {
        faction_id   => $c->{faction_id},
        faction_name => $c->{faction_name},
        disposition  => $c->{disposition} // 'unknown',
    },
    irritation => $c->{irritation} // 0,
};
```

**After**: Include `pending_counter` if present:
```perl
$market_view = {
    customer => {
        faction_id      => $c->{faction_id},
        faction_name    => $c->{faction_name},
        disposition     => $c->{disposition} // 'unknown',
        ($c->{pending_counter}
            ? (pending_counter => $c->{pending_counter})
            : ()),
    },
    irritation => $c->{irritation} // 0,
};
```

**Tests**: Update `t/market_visit_web.t` to verify `pending_counter` appears
in game state after a counter-offer is generated.

---

### 2. Add counter-offer acceptance UI in `game.js`

**File**: `public/js/game.js`

#### 2a. `renderMarketVisit()` — add counter-offer section

When `customer.pending_counter` is present, show:

```
┌─────────────────────────────────────────────┐
│ Market Visit                                │
│ Customer: The Syndicate                     │
│ [narrative message from API]                │
│                                             │
│ [Accept Counter-Offer (15 scrap)]           │
│                                             │
│ (or offer a different artifact to reject)   │
│                                             │
│ Select an artifact to offer:                │
│ [item list with Offer buttons]              │
│                                             │
│ [Send Away]                                 │
└─────────────────────────────────────────────┘
```

The counter-offer section replaces the generic "Select an artifact" intro with
the specific counter-offer message + Accept button. The shed items remain
shown so the player can offer a different item (implicit rejection).

#### 2b. Inline response handling in `offerItem()` and `acceptCounter()`

Both functions will:
1. POST to the API endpoint
2. Read the response `result`, `message`, and any updated state (`player`,
   `irritation`, `counter_value`, etc.)
3. Update `G.market_visit` / `G.player` from the response
4. Call `renderActionCard()` (which calls `renderMarketVisit()`) to show the
   message and updated state inline
5. Only call `loadGame()` for terminal results where the activity is destroyed
   (`sent_away`, `customer_left`) or as a fallback for unexpected states

Key response results to handle:
- `counter_offer`: Show message, render Accept button alongside shed items
- `sold_more` (multi-item): Show "Sold for X scrap!" + customer mood text,
  re-render market card with updated irritation, reduced shed
- `sold` (single-item): `loadGame()` — activity gone, back to idle
- `no_match`: Show message, re-render with updated irritation
- `over_budget`: Show message, re-render with updated irritation
- `sent_away` / `customer_left`: `loadGame()`

#### 2c. `acceptCounter()` function

```js
async function acceptCounter() {
  const data = await api('/market/accept_counter', { method: 'POST' });
  if (data.ok) {
    // handle result inline following same pattern as offerItem
  }
}
```

#### 2d. Wire in `wireActionButtons()`

Add:
```js
document.getElementById('btn-accept-counter')?.addEventListener('click', acceptCounter);
```

---

### 3. Add web integration tests

**File**: `t/market_visit_web.t`

Use deterministic test setups:
- For **mismatch tests**: Use an item with a behavior tag no faction desires
  (e.g. `defense`) to guarantee mismatch. Force `settle_chance => 0` by
  directly manipulating the activity's customer hash in the test setup.
- For **match tests**: Use `thermal` (intersects 2 factions) or directly set
  `desired_behaviors` on the customer via the model in test setup.

| Test | Config | Approach |
|------|--------|----------|
| `counter-offer generated on mismatch` | `market_counter_offers => 1` | Item with `behaviors => ['defense']`, verify `counter_offer` result |
| `accept_counter sells at counter price` | `market_counter_offers => 1` | Begin → offer mismatch → counter_offer → accept_counter → verify `sold` + disposition |
| `counter-offer visible in game state` | `market_counter_offers => 1` | After counter_offer, GET `/game` and verify `pending_counter` in response |
| `multi-item allows multiple sales` | `market_multi_item => 1` | Match item → `sold_more` → offer another → `sold_more` → send_away |
| `send_away works` | Default | `/market/send_away` clears activity, player back to idle |
| `customer_left when irritation threshold hit` | `market_counter_offers => 0` | Multiple mismatches trigger `customer_left` result |

---

## Files Changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Controller/Game.pm` | Expose `pending_counter` in market_view |
| `public/js/game.js` | Counter-offer UI + inline response handling for offerItem/acceptCounter |
| `t/market_visit_web.t` | Web tests for both features |

---

## What Does NOT Change

- No backend game logic changes in `MarketVisit.pm` (all activity logic complete).
- No new routes or controller actions.
- No config default changes (both features remain disabled by default).
- No template changes (UI is entirely client-side via `game.js`).
- No budget or threshold data exposed to the client — only narrative-level
  information (`message`, `result`, `irritation`, `counter_value`, `player` snapshot).

---

## Verification

```bash
prove -lv t/market_visit_web.t
```
