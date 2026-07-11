# Mountain Dominance Display

Replace the personal-standing faction registry with a PB3K terrain-scan
visualization of the Mountain showing global faction dominance.

## What Changes

- **FACTIONS tab** (secondary panel, `/factions?_format=fragment`):
  Replaces the current faction registry (personal standing stars) with a
  Mountain terrain-scan chart showing global faction dominance rankings.
  Every faction glyph and name is clickable → faction reference sheet in
  the other panel (reuses existing `data-reference-id` mechanism).

- **HOME dashboard** (primary panel, `/home?_format=fragment`):
  Adds a compact "TOP SALES" line at the bottom showing the player's
  personal faction standing leader.

The JSON endpoint `/factions` (no `_format`) is unchanged — still returns
faction definitions, standing, faction_sales, faction_state.

---

## Backend: DominanceService

Add `ranked_factions($season)` returning all 5 factions sorted by
influence with ratio vs leader.

```perl
sub ranked_factions ($self, $season) {
    my $fs = $season->getCol('faction_state') // return [];
    my @rank = sort { $fs->{$b}{influence} // 0 <=> $fs->{$a}{influence} // 0 } keys %$fs;
    my $leader = $rank[0] ? ($fs->{$rank[0]}{influence} // 1) : 1;
    return [ map { +{
        faction_id => $_,
        rank       => ...,
        influence  => $fs->{$_}{influence} // 0,
        ratio      => ($fs->{$_}{influence} // 0) / $leader,
    } } @rank ];
}
```

Pure derived data — no new state, no new persistence. The data already
exists in `faction_state`.

---

## Backend: FactionsController (fragment handler)

Replace the personal-standing stars logic in the `_format=fragment` path:

1.  Call `$self->app->dominance_service->ranked_factions($season)`
2.  Merge ranked data with faction definitions (name, icon URL,
    short_name, disposition) from `factions_data`
3.  Read `faction_climate` from season for intensity tier
4.  Stash `factions` (merged, ranked array), `faction_climate`
5.  Compute the raster from intensity tier (see below)
6.  Stash `mountain_raster` (array of strings, one per row)
7.  Render `factions/mountain_chart` (new template)

The JSON path (no `_format`) stays exactly as-is:
- Returns `factions` (raw definitions), `standing`, `faction_sales`,
  `faction_state`
- No changes to the mobile SPA

---

## Backend: HomeController

Add one line to the fragment handler:

```perl
my $sales = $char->getCol('faction_sales') // {};
my $top = ...;  # find faction with highest sales, compute star count
$self->stash(top_sales_line => "SYND.8TE ★★★★★");
```

---

## Raster Generation

The mountain raster is a fixed triangular shape (10 rows × 9 chars at
widest). Characters vary by intensity tier:

| Tier | Character distribution | Effect |
|------|----------------------|--------|
| CONTESTED | ~40% `░`, 30% `▓`, 30% `█` | Heavy noise — scan is fragmented |
| LEADING | ~10% `░`, 40% `▓`, 50% `█` | Some noise, scan is fuzzy |
| STRONG | ~0% `░`, 20% `▓`, 80% `█` | Stable, solid reading |
| DOMINANT | ~0% `░`, 10% `▓`, 90% `█` | Crisp, clear summit |

The mountain shape is always the same (a triangle). Only the fill
characters change. No faction-to-pixel mapping — the raster is purely
decorative/diegetic terrain scan.

Implementation sketch:

```perl
sub _build_raster ($self, $tier) {
    my %dist = (
        contested => [0.3, 0.3, 0.4],  # solid, mid, sparse
        leading   => [0.5, 0.4, 0.1],
        strong    => [0.8, 0.2, 0.0],
        dominant  => [0.9, 0.1, 0.0],
    );
    my $d = $dist{$tier} || $dist{contested};
    my $shape = $self->_mountain_shape;
    my @rows;
    for my $row (@$shape) {
        my @chars;
        for my $cell (@$row) {
            if (!$cell) { push @chars, ' '; next; }
            my $r = rand;
            push @chars, $r < $d->[0] ? '█'
                       : $r < $d->[0]+$d->[1] ? '▓'
                       : '░';
        }
        push @rows, join('', @chars);
    }
    return \@rows;
}
```

Diegetic justification: the PB3K terrain scanner gets a cleaner reading
when one faction clearly controls the Mountain. When the race is tight,
interference from faction activity degrades the scan.

---

## Templates

### New: `templates/factions/mountain_chart.html.ep`

```
┌──────────────────────────────────┐
│  TERRAIN SCAN  :  DOMINANT       │ ← header
│                                  │
│      ▓▓        ◆  SYND.8TE      │ ← rank 1, summit
│     ████                         │
│     █████      ▲  PURIF.RS       │ ← rank 2
│    ██████                        │
│    ███████    █  FAC.LTY1        │ ← rank 3
│   ████████                       │
│  █████████    ▀  LBR_MT.01       │ ← rank 4
│  █████████                       │
│ ██████████   ▓  RVL_IST.1        │ ← rank 5
│ ███████████                      │
└──────────────────────────────────┘
```

Template structure:

```html
<div class="mm-mountain">
  <div class="mm-mountain-header">
    TERRAIN SCAN  :  <%= $cc->{intensity_label} // '' %>
  </div>
  <div class="mm-mountain-body">
    <pre class="mm-mountain-raster"><%== join "\n", @$raster %></pre>
    <div class="mm-mountain-list">
      % for my $f (@$factions) {
      <div class="mm-mountain-faction" data-reference-id="faction_<%= $f->{faction_id} %>">
        <img src="<%= $f->{icon} %>" alt="" class="mm-mountain-glyph">
        <span class="mm-mountain-name"><%= $f->{short_name} %></span>
        % if ($f->{rank} == 1 && $cc->{intensity_label}) {
        <span class="mm-mountain-badge"><%= $cc->{intensity_label} %></span>
        % }
      </div>
      % }
    </div>
  </div>
</div>
```

Click-to-reference: `data-reference-id="faction_<id>"` on each faction
row div. The existing `game.js:335-341` catches `[data-reference-id]`
clicks and fetches `/reference/faction_<id>?_format=fragment` into
`#secondary-content`. Zero new JS.

### Modified: `templates/home/dashboard.html.ep`

Add at the bottom after the salvage ledger:

```html
% if (my $line = stash('top_sales_line')) {
<div class="mm-text-dim mm-margin-top-sm mm-top-sales">
  TOP SALES: <%== $line %>
</div>
% }
```

(Dashboard line 32 is the salvage ledger include — append after it.)

---

## CSS

All new classes belong in `public/css/app.css`:

| Class | Purpose |
|-------|---------|
| `.mm-mountain` | Flex column container, panel border, padding |
| `.mm-mountain-header` | Amber header text with intensity label |
| `.mm-mountain-body` | Flex row: raster left, faction list right, gap |
| `.mm-mountain-raster` | `<pre>`: monospace, ~0.45rem font, amber, white-space pre, leading 1.1, no margin |
| `.mm-mountain-list` | Flex column, justify-content space-around |
| `.mm-mountain-faction` | Flex row, align-items center, gap 0.4rem, cursor pointer |
| `.mm-mountain-glyph` | 24px × 24px, flex-shrink 0, vertical-align middle |
| `.mm-mountain-name` | ref-link style (dashed underline, amber), cursor pointer |
| `.mm-mountain-badge` | Small amber badge, 0.65rem, border, padding |
| `.mm-top-sales` | 0.7rem dim text, margin-top 0.5rem |

Mobile breakpoint (<= 400px):

| Change | Why |
|--------|-----|
| Raster font: 0.35rem | Fits 3-char wide strip on narrow screens |
| Glyph: 20px | Saves horizontal space |
| List gap tightens | Vertical space |
| Badge hidden | Saves space; intensity is in header |

---

## Raster Shape

```perl
sub _mountain_shape ($self) {
    [
        [0,0,0,0,1,0,0,0,0],   # peak
        [0,0,0,1,1,1,0,0,0],
        [0,0,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1],   # base
    ];
}
```

Subtly asymmetric — slightly wider right side — so it reads as a scan
of a real terrain feature rather than a precise geometric pyramid.

---

## Tests

### `t/fragment_web.t`

Replace the "factions fragment returns registry with reference links"
subtest:

```perl
subtest 'factions fragment shows mountain dominance chart' => sub {
    my $t = setup_with_dominance;
    $t->get_ok('/factions?_format=fragment')
      ->status_is(200)
      ->content_like(qr{TERRAIN SCAN}, 'mountain chart')
      ->content_like(qr{data-reference-id="faction_syndicate"}, 'ref link')
      ->content_like(qr{█}, 'raster char present');
};
```

A setup helper `setup_with_dominance` creates a season with known
`faction_state` values (e.g. syndicate 50, purifiers 30, etc.) so the
dominance service has data to rank.

### `t/faction_stars.t`

Rewrite to test the mountain chart. Instead of setting `faction_sales`
on the character:

1.  Set `faction_state` on the season with known influence values
2.  Fetch `/factions?_format=fragment`
3.  Assert:
    - Factions rendered in rank order (use ordered regex)
    - `data-reference-id` attributes present for all 5
    - Intensity label matches margin (e.g. margin 20 → "STRONG")
    - Raster characters ( █ ▓ ░ ) present

### `t/controller_web.t`

No change — JSON endpoint is untouched.

---

## Walkthrough

Search `bin/walkthrough` for any assertion on "FACTION REGISTRY" or
star characters (`★`) in the factions fragment. Update those lines.

Walkthrough should visit `/factions?_format=fragment` and verify the
new chart renders (e.g. check for "TERRAIN SCAN" in the response).

---

## Sequence

1. Add `ranked_factions`, `_build_raster`, `_mountain_shape` to
   `Dominance.pm`
2. Rewrite fragment handler in `FactionsController.pm`
3. Add `top_sales_line` to `HomeController.pm`
4. Create `templates/factions/mountain_chart.html.ep`
5. Delete `templates/factions/registry.html.ep`
6. Add `top_sales_line` render to `templates/home/dashboard.html.ep`
7. Add CSS classes to `public/css/app.css`
8. Rewrite `t/faction_stars.t`
9. Update `t/fragment_web.t`
10. Update `bin/walkthrough`
11. `make ci-check && make cover && make report`

---

## What Does NOT Change

- JSON responses for `/factions`, `/game`, `/home` (no `_format`)
- The reference endpoint (`/reference/:id`) and faction reference data
- `game.js` event delegation — click-to-reference already works
- Climate card on HOME — stays text-based
- Nav controller, routing, activity system, season maintenance
- Any data persistence or model files
