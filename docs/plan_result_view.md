# Plan: Result View for Terminal Outcomes

## Problem

After a terminal outcome (sold last item, customer stormed off, collapse,
breakthrough, stop), the activity is deleted and the fragment endpoint returns
204 — a blank panel. The player saw scrap/score change in the status strip but
got no narrative feedback about what happened or why.

Non-terminal outcomes (`sold_more`, `counter_offer`, `no_match`) already render
inline via the `last_sale` card in the market negotiation panel. That stays.

## Solution

A transient `result` view rendered as the primary fragment. The same
declarative pipeline (nav → fragment) handles it with no JS changes.

## New Files

### `lib/MagicMountain/Controller/Result.pm`

Two actions:

- **`show`** — reads `$char->getCol('result')`. If present, renders the result
  fragment (200). If absent, returns 204.
- **`dismiss`** — `POST /result/dismiss`. Calls `$char->nullCol('result')` and
  `$char->setCol('current_view', 'home')`, then `$char->save`. Returns
  `{ ok: 1 }`. Must be under `$auth_write` (CSRF-protected) in routes.

### `templates/result/show.html.ep`

Renders the outcome card. Consumes `$result` from stash:

```html
<div class="mm-panel">
  <div class="mm-panel-header">RESULT</div>
  <div class="mm-panel-body">
    <p><strong><%= $result->{icon} %></strong> <%= $result->{outcome_text} %></p>
    <p><%= $result->{item_name} %></p>
% if (defined $result->{value}) {
    <p><%= $result->{value} %> scrap</p>
% }
    <p><%= $result->{message} %></p>
    <button class="mm-btn mm-btn-primary" data-action-url="/result/dismiss"
            data-method="POST">Continue</button>
  </div>
</div>
```

ICON and OUTCOME_TEXT vary by outcome:

| Outcome | Icon | Text |
|---------|------|------|
| `sold` | SCRAP | Sold! |
| `customer_left` | ALERT | Customer Stormed Off |
| `sent_away` | WAIT | No Sale |
| `collapse` | ALERT | Artifact Collapsed |
| `breakthrough` | PREMIUM | Breakthrough! |

## Changes

### `lib/MagicMountain/Model/Character.pm`

Add `result` to the `columns` arrayref. No validator needed — it's a text
column (JSON-serialized hashref by Model).

### `lib/MagicMountain/Controller/Nav.pm`

Add `result` to four maps:

```perl
my %FRAGMENT_URL = (
    ...,
    result => '/result?_format=fragment',
);

my %SECONDARY = (
    ...,
    result => 'factions',
);

Add `result` to `_tab_id_for` so HOME tab stays highlighted:

```perl
sub _tab_id_for ($view) {
    my %map = (
        home        => 'home',
        idle        => 'prospect',
        result      => 'home',
        prospecting => 'prospect',
        market      => 'bazaar',
        factions    => 'factions',
        skills      => 'skills',
        account     => 'account',
    );
    return $map{$view} || 'home';
}
```

`%BASE_TAB` needs no entry — the `result` view has no tab.

`%TAB_FRAGMENT_URL` needs no entry — result is not a tab destination.

### `lib/MagicMountain.pm` — routes

```perl
$auth->get('/result')->to('result#show')->name('result_show');
$auth_write->post('/result/dismiss')->to('result#dismiss')->name('result_dismiss');
```

### `lib/MagicMountain/Activity/MarketVisit.pm`

In `_do_sale` (when no items remain or single-item mode), in
`send_away`, and in the customer-left path in `offer`:

```perl
$char->setCol('result', {
    outcome   => 'sold',       # or 'customer_left', 'sent_away'
    value     => $v,
    message   => $text,
    item_name => $artifact_id,
});
$char->setCol('current_view', 'result');
$char->save;
```

### `lib/MagicMountain/Activity/Prospecting.pm`

In collapse and breakthrough paths in `push`. **Not** on `stop` — the player
chose to stop and the artifact went to the shed; nav falls back to home where
the shed ledger shows the new item.

```perl
# collapse (in _do_collapse, before $char->save)
$char->setCol('result', { outcome => 'collapse', item_name => $artifact->{id} });
$char->setCol('current_view', 'result');
$char->save;

# breakthrough (in _do_breakthrough, before $char->save)
$char->setCol('result', { outcome => 'breakthrough', value => $new_value, item_name => $artifact->{id} });
$char->setCol('current_view', 'result');
$char->save;
```

## What Does NOT Change

- JS (`game.js`) — no changes. `handleAction` already calls `applyNav()`,
  which fetches `/nav` and renders whatever fragment URL comes back.
- The `last_sale` card during multi-item negotiation (rendered inline). Only
  affected when the *visit ends* (last item sold).
- Tab active/inactive rules — result is an idle-state view.
- Walkthrough — the existing flow ends with `DELETE /sessions` (logout). The
  result view appears briefly during normal play but doesn't affect the
  walkthrough's HTTP-level assertions.

## Lifecycle

```
User action → POST /market/offer
  → Activity handler: sale, collapse, etc.
    → Store result on character, set current_view = 'result', save
    → Delete activity row
  → Controller: return JSON
  → JS handleAction: applyNav()
    → GET /nav → current_view = 'result'
      → primary_fragment_url = /result?_format=fragment
      → GET /result → 200 + fragment
        → User sees result card
          → Click "Continue" → POST /result/dismiss
            → Clear result + current_view, set home
            → applyNav() → back to normal
```

## Resolved

1. **Stopped**: No result view. Nav falls back to home — the shed ledger
   shows the new item. Clear enough.
2. **current_view in JSON**: Not needed. The handler sets `current_view` on
   the character before returning the view hash. When JS calls `applyNav()`
   → `GET /nav`, the stored value is already there. Redundant to also send
   it in the POST response.
