# UI Redesign — Implementation Plan

See `docs/nav_state_rules.md` for the view model and tab rules that this plan implements.

## Overview

Transform the current stacked-panel layout into a fixed-frame device UI with pinned chrome and a two-panel center area. Nav state is managed by a Perl endpoint (`GET /nav`) that returns the current view, tab active states, tab fragment URLs, primary/secondary view fragment URLs, and context bar text. JS is purely declarative — it renders what the server tells it and does not compute URLs or game state.

---

## Phase 1: Nav Controller + Endpoint

### Files
- `lib/MagicMountain/Controller/Nav.pm` — new controller
- `t/nav_web.t` — new test file

### Controller (`Nav.pm`)

`GET /nav` endpoint. Reads character state, builds response. All view transitions are allowed unless they conflict with an active activity (can't visit bazaar while prospecting, can't start a new expedition while at market).

```perl
package MagicMountain::Controller::Nav;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $type = $self->_active_activity_type($char);
    my $ap   = $char->getCol('action_points') // 0;
    my $shed_count = scalar @{ $self->app->shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') }) };

    my $view = $type || 'idle';
    my $tabs = _build_tabs($type, $ap, $shed_count);
    my $secondary = _secondary_for($view);
    my $context = _context_text($char, $type, $view);

    $self->render(json => {
        current_view           => $view,
        primary_fragment_url   => _fragment_url($view),
        secondary_view         => $secondary,
        secondary_fragment_url => _fragment_url($secondary),
        tabs                   => $tabs,
        context                => $context,
    });
}

my _build_tabs ($type, $ap, $shed_count) {
    my $base = _base_tab_states($type);  # rules from nav_state_rules.md Table
    # Resource-based overrides: BAZAAR needs AP + shed items
    if ($ap < 1) {
        $base->{bazaar}{active} = 0;
        $base->{bazaar}{reason} = 'No AP remaining';
    }
    elsif ($shed_count < 1) {
        $base->{bazaar}{active} = 0;
        $base->{bazaar}{reason} = 'No artifacts in shed';
    }
    return [map { {
        id            => $_,
        label         => _tab_label($_),
        active        => $base->{$_}{active},
        reason        => $base->{$_}{reason},
        fragment_url  => _fragment_url($_),
    } }, keys %$base ];
}

my _secondary_for ($view) {
    my %map = (
        idle     => 'shed',
        prospect => 'shed',
        market   => 'factions',
        shed     => 'factions',
        factions => 'leaderboard',
        skills   => 'leaderboard',
        bulletin => 'leaderboard',
    );
    return $map{$view} // 'shed';
}

my _fragment_url ($view) {
    my %url = (
        idle     => '/idle?_format=fragment',
        prospect => '/prospecting?_format=fragment',
        market   => '/market?_format=fragment',
        shed     => '/shed?_format=fragment',
        factions => '/factions?_format=fragment',
        skills   => '/skills?_format=fragment',
        bulletin => '/crier?_format=fragment',
    );
    return $url{$view};
}

my _tab_label ($view) {
    my %label = (
        idle     => 'PROSPECT',
        prospect => 'PROSPECT',
        market   => 'BAZAAR',
        shed     => 'SHED',
        factions => 'FACTIONS',
        skills   => 'SKILLS',
        bulletin => 'BULLETIN',
    );
    return $label{$view};
}
```

### Nav endpoint response shape

`GET /nav` returns:

```json
{
  "current_view": "prospect",
  "primary_fragment_url": "/prospecting?_format=fragment",
  "secondary_view": "shed",
  "secondary_fragment_url": "/shed?_format=fragment",
  "tabs": [
    {"id": "prospect", "label": "PROSPECT",  "active": true,  "reason": null, "fragment_url": "/prospecting?_format=fragment"},
    {"id": "shed",     "label": "SHED",      "active": true,  "reason": null, "fragment_url": "/shed?_format=fragment"},
    {"id": "bazaar",   "label": "BAZAAR",    "active": false, "reason": "Finish your current expedition first", "fragment_url": "/market?_format=fragment"},
    {"id": "factions", "label": "FACTIONS",  "active": true,  "reason": null, "fragment_url": "/factions?_format=fragment"},
    {"id": "skills",   "label": "SKILLS",    "active": true,  "reason": null, "fragment_url": "/skills?_format=fragment"},
    {"id": "bulletin", "label": "BULLETIN",  "active": true,  "reason": null, "fragment_url": "/crier?_format=fragment"}
  ],
  "context": "INSTABILITY 7/14  |  STAGE STRAINED  |  [PUSH]  [STOP]"
}
```

Key design: `fragment_url` is in every tab object AND in `primary_fragment_url`/`secondary_fragment_url` at the top level. JS never computes a URL.

### Route
In `MagicMountain.pm`:
```perl
$auth->get('/nav')->to('nav#show');
```

### Test (`t/nav_web.t`)

| Subtest | What it checks |
|---------|---------------|
| idle state | `current_view` = idle, all tabs active, URLs present |
| idle no AP | bazaar inactive with "No AP remaining" reason |
| idle empty shed | bazaar inactive with "No artifacts" reason |
| prospecting | `current_view` = prospect, bazaar inactive |
| market visit | `current_view` = market, prospect inactive |
| context text | non-empty string per state |
| secondary_view | correct panel per view |
| fragment_urls | all URLs non-empty, start with `/` |
| tab click during idle | requesting shed via header — `current_view` = shed |
| tab click during idle with no AP | requesting bazaar — returns `current_view` = idle (bazaar inactive) |
| tab click during prospecting | requesting bazaar — returns `current_view` = prospect (bazaar inactive) |
| tab click during market | requesting idle — returns `current_view` = market (idle tab inactive) |
| after prospecting begin | simulate begin, hit /nav — `current_view` = prospect |
| after prospecting stop | simulate stop, hit /nav — `current_view` = idle |
| after market begin | simulate begin, hit /nav — `current_view` = market |

Transition tests work by setting up character state (AP, shed items, pending activity), then calling `GET /nav` and asserting the expected `current_view` and tab states. No real HTTP action calls needed — just create the character and activity rows directly via Model objects.

---

## Phase 2: JS — applyNav replaces refetchFragments

### Files
- `public/js/game.js`

### Changes

**Boot flow:**
```js
async function loadGame() {
  G = await api('/game');
  populateStatusStrip(G);
  await applyNav();
}
```

The `populateStatusStrip` function fills DAY/AP/SCRAP/SCORE into `#status-strip` from G, and sets `#device-owner` to `G.player.name`. No `render()` call — all panel content comes from `/nav` + fragment fetches.

**After every action:**
```js
async function applyNav() {
  const nav = await api('/nav');
  renderNavBar(nav.tabs);
  document.getElementById('context-bar').textContent = nav.context;
  const fetches = [
    fetchThenRender(nav.primary_fragment_url, 'panel-primary'),
    fetchThenRender(nav.secondary_fragment_url, 'panel-secondary'),
  ];
  await Promise.all(fetches);
}
```

`fetchThenRender(url, targetId)` fetches a fragment and sets `innerHTML`. JS does not map view names to URLs — the server provides them.

**Nav bar click:**
```js
document.getElementById('nav-bar').addEventListener('click', (e) => {
  const btn = e.target.closest('[data-view]');
  if (!btn || btn.classList.contains('inactive')) return;
  applyNav();  // re-fetch /nav — server returns the view the tab requested
});
```

The server determines what `current_view` to return based on the tab clicked and the current activity constraints. JS just calls `applyNav()`.

**Event delegation targets change** — the slot containers (`#slot-shed`, `#slot-action`, `#slot-skills`) are removed in Phase 3. Delegation moves to the new panels:

```js
document.getElementById('panel-secondary').addEventListener('click', (e) => {
  const btn = e.target.closest('.offer-btn');
  if (btn) offerItem(btn.dataset.id);
});

document.getElementById('panel-primary').addEventListener('click', (e) => {
  const id = e.target.id;
  if (id === 'btn-push') pushArtifact();
  else if (id === 'btn-stop') stopProspecting();
  else if (id === 'btn-begin') beginProspecting();
  else if (id === 'btn-market') beginMarket();
  else if (id === 'btn-send-away') sendAway();
  else if (id === 'btn-accept-counter') acceptCounter();
  const btn = e.target.closest('.buy-skill-btn');
  if (btn) purchaseSkill(btn.dataset.skill);
});
```

### Functions removed from JS
- `renderActionFragment()` — replaced by `applyNav()`
- `renderProspectingFragment()` — replaced by server-provided fragment URLs
- `renderMarketFragment()` — replaced by server-provided fragment URLs
- `refetchFragments()` — replaced by `applyNav()` single fetch
- `renderRecap()` — removal deferred; can be shown via dedicated view or idle fragment
- `renderPlayerFragment()` — player data moved to status strip
- `renderShedFragment()`, `renderCrierFragment()`, `renderSkillsFragment()`, `renderFactionsFragment()`, `renderLeaderboardFragment()` — all replaced by server-provided fragment URLs

### Action handlers simplified

All action handlers remove `G.prospecting`, `G.market_visit`, and `G.player` writes. These G fields were only consumed by `renderActionFragment()` (dispatch) and `render()` (status strip), both replaced by `/nav` and `populateStatusStrip()`.

**Before (in every handler):**
```js
if (data.player) Object.assign(G.player, data.player);
if (data.artifact) G.prospecting = data.artifact;
else G.prospecting = null;
G.market_visit = { customer: data.customer || {} };
updateStats();
renderActionCard();
if (data.refetch) await refetchFragments(data.refetch);
else await loadGame();
```

**After:**
```js
if (data.refetch) await applyNav();
else await loadGame();
```

The `/nav` endpoint determines the correct view from server state (active activity type, AP, shed count). JS no longer mirrors game state in G for rendering purposes. The only exception: `loadGame()` fetches `/game` once on boot to populate the status strip and device header — subsequent updates come from fragment fetches.

### `loadGame()` preserved
`GET /game` is still called on boot to populate `G.player.name` (device header) and `G.season` (status strip day count). After boot, all rendering comes from `/nav` + fragment fetches. `G` is no longer updated on action responses. No `Object.assign(G.player, ...)`, no `G.prospecting`, no `G.market_visit` writes survive.

---

## Phase 3: Device Frame + Chrome (CSS + template)

### Files
- `templates/game/show.html.ep`
- `public/css/app.css`

### Template structure
```html
<div id="device-frame">
  <div id="device-header">
    <div id="device-name">THE PROSPECTBOY 3000 // LOCAL NODE 07</div>
    <div id="device-meta">OS v2.1.4  │  REGISTERED TO: <span id="device-owner">—</span></div>
  </div>
  <div id="status-strip">
    <span>DAY  <span id="s-day">—</span>/<span id="s-total">—</span></span>
    <span>AP   <span id="s-ap">—</span></span>
    <span>SCRAP <span id="s-scrap">—</span></span>
    <span>SCORE <span id="s-score">—</span></span>
  </div>
  <div id="nav-bar"></div>        <!-- populated by JS from /nav tabs -->
  <div id="main-area">
    <div id="panel-primary"></div>    <!-- populated by JS from primary_fragment_url -->
    <div id="panel-secondary"></div>  <!-- populated by JS from secondary_fragment_url -->
  </div>
  <div id="context-bar"></div>    <!-- populated by JS from /nav context -->
</div>

<div id="device-footer">
  <a href="/logout">Leave the Mountain</a>
  <button id="delete-account-btn">Delete Account</button>
  % if ($season_is_active) {
    <button id="btn-end-season">End Season</button>
  % }
</div>
```

### Player template simplification
`templates/player/status.html.ep` currently shows player name, AP, scrap, and score. After the redesign, AP/scrap/score are in the pinned `#status-strip`. The player fragment should be stripped to only show the player name or a device greeting — AP/scrap/score cells are redundant and should be removed.

### CSS
- `#device-frame`: max-width ~48rem, centered, border + subtle bezel, max-height: 95vh
- `overflow: hidden` at frame level; panel content scrolls individually
- `#status-strip`: CSS grid with equal `ch`-based columns
- `#nav-bar`: flex row, `[ LABEL ]` bracket styling via `::before`/`::after`
- `#main-area`: flex row, 2:1 primary:secondary
- `#panel-secondary`: hidden via media query below 600px
- `#context-bar`: fixed-height bottom row, monospace
- `#device-footer`: small centered text below the frame, outside the bezel

---

## Phase 4: Cleanup

- Remove `%REFETCH` hash and `refetch` key from `Controller.pm::_render_action` — no longer consumed by JS
- Remove all old slot containers from template
- Simplify `templates/player/status.html.ep` — remove AP/scrap/score cells (now in pinned status strip)
- Generate `docs/dead_code_inventory.md` listing every endpoint, template, JS function, and CSS class that is safe to remove
- Run `make cover && make report` to verify coverage stays above 85%

---

## Verification

| Step | Command |
|------|---------|
| JS syntax | `make test-js` |
| Full test suite | `prove -l t/` |
| Smoke test page | `bash bin/smoke_test_endpoint GET /game` |
| Nav controller | `bash bin/smoke_test_endpoint GET /nav` |
| Coverage | `make cover && make report` |

All tests pass. Coverage stays above 85%.
