# Magic Mountain UI Redesign Plan

Target: Amber ANSI terminal aesthetic via the ProspectBoy 3000, per `docs/design_bible.md`.

---

## Architectural Change: Distributed Fragment Resources

The core architectural shift: instead of building UI in JS template literals, the
server renders HTML fragments that JS fetches and inserts.

Each fragment comes from a **web resource endpoint**. Controllers represent
resources (Rails model). The frontend fetches from resource endpoints saying
"give me this resource as an HTML fragment" via `respond_to` format negotiation.

```
GET /player        →  Player resource (JSON data)
GET /player.html   →  Player resource (full page)
GET /player?_format=fragment →  Player resource (HTML fragment for embedding)
```

This keeps frontend and backend decoupled. The frontend can rearrange panels,
combine or split fragments, without backend changes. The backend just serves
resource representations.

### Content Negotiation via `_format` Query Parameter

Mojolicious's `respond_to` helper dispatches based on format. The frontend
requests a specific format using the `_format` query parameter (not URL
extensions — those require route-level format constraints that would add
complexity to every route).

**Flow:**

1. Register a `fragment` MIME type in `MagicMountain.pm` startup:
   ```perl
   $self->types->type(fragment => 'text/html');
   ```

2. Each resource controller uses `respond_to` with a `fragment` handler:
   ```perl
   sub show ($self) {
       $self->respond_to(
           html     => sub { $self->render('game/show') },   # full page
           fragment => sub { $self->render('player/fragment') },  # embeddable HTML
           json     => sub { $self->render(json => $data) }, # raw data
       );
   }
   ```

3. Frontend fetches via `?_format=fragment` query parameter:
   ```javascript
   let html = await fetch('/player?_format=fragment').then(r => r.text());
   ```

**Why `_format` and not URL extensions (`.fragment`):**

In Mojolicious, URL format extensions (`.json`, `.fragment`) are only
captured by route patterns that have explicit format constraints
(e.g., `$auth->under('/' => [format => ['json', 'fragment']])`). Adding
format constraints to every resource route is invasive and error-prone.
The `_format` query parameter is the standard Mojolicious mechanism for
format negotiation without route changes. The `accepts` method in the
Renderer checks `_format` first, then falls back to the Accept header.

**Note on MIME type registration:** `$self->types->type(fragment => 'text/html')`
maps the format name `fragment` to the MIME type `text/html`. When
`respond_to` receives a request with `_format=fragment`, it looks for a
`fragment => sub { ... }` handler and dispatches to it. The same MIME type
as `html` is intentional — fragments ARE HTML, just partial pages.

### Data Flow

```
Page load:
  GET /game (text/html)  →  empty CSS-grid shell with placeholder <div>s
  ─────────────────────────────────────────────────────────────
  GET /player?_format=fragment        →  status strip HTML
  GET /season?_format=fragment        →  season info HTML
  GET /crier?_format=fragment         →  bulletin feed HTML
  GET /prospecting?_format=fragment   →  prospecting panel or 204 (idle)
  GET /market?_format=fragment        →  market panel or 204 (idle)
  GET /shed?_format=fragment          →  salvage ledger HTML
  GET /skills?_format=fragment        →  training records HTML
  GET /factions?_format=fragment      →  faction registry HTML
  GET /leaderboard?_format=fragment   →  rankings HTML
  All parallel

After action (e.g., POST /prospecting/push):
  Server returns JSON:
    { ok: 1, result: "pushed", csrf_token: "...", refetch: ["prospecting", "player"] }
  Frontend loops over refetch list, re-fetches each fragment:
    GET /prospecting?_format=fragment  →  updated panel
    GET /player?_format=fragment       →  updated AP/score

  The `refetch` array is the server's declaration of which resources changed.
  The frontend treats it as opaque — it just re-fetches every name in the list.

CSRF token: embedded in shell page on initial load. Returned in every
POST response. Frontend stores and resubmits via X-CSRF-Token header.
```

### Resource Endpoints

| Resource | Endpoint | Controller | Purpose |
|----------|----------|------------|---------|
| Game shell | `GET /game` | Game#show | Empty shell with placeholders |
| Player stats | `GET /player` | Player#show | Status strip (AP, scrap, score) |
| Season info | `GET /season` | Season#show | Day/total, active indicator |
| Crier | `GET /crier` | Crier#show | Bulletin feed |
| Idle actions | `GET /idle` | Idle#show | Action buttons when no activity active |
| Prospecting | `GET /prospecting` | Prospecting#show | Field scan panel (or 204) |
| Market | `GET /market` | Market#show | Buyer negotiation (or 204) |
| Shed | `GET /shed` | Shed#show | Salvage ledger |
| Skills | `GET /skills` | Skills#show | Training records |
| Factions | `GET /factions` | Factions#show | Faction registry with icons |
| Leaderboard | `GET /leaderboard` | Leaderboard#show | Rankings snapshot |

Activity-aware loading order:

1. Frontend fetches `GET /prospecting?_format=fragment` and
   `GET /market?_format=fragment` in parallel alongside all other fragments.
2. If both return 204, the action slot is empty. Frontend then fetches
   `GET /idle?_format=fragment` for the idle action buttons.
3. If either returns content, that content fills the action slot directly.

This avoids double-fetching the activity endpoints in the common case
(activity is active).

### Template Tree

Fragments live with their controller's template directory:

```
templates/
  layouts/
    default.html.ep              ← terminal-style layout (Bootstrap still loaded, removed in Phase 9)
  components/
    faction_icon.html.ep         ← inline SVG, takes faction_id param
    artifact_icon.html.ep        ← inline SVG for category glyphs
    terminal_panel.html.ep       ← wrapper with title bar, content slot
    instability_meter.html.ep    ← block-bar meter (shared)
  game/
    show.html.ep                 ← CSS grid shell with placeholder divs
  player/
    fragment.html.ep             ← status strip: DAY AP SCRAP SCORE
  season/
    fragment.html.ep             ← day/total, SEASON ACTIVE badge
  crier/
    fragment.html.ep             ← CRIER / BULLETIN feed
  idle/
    fragment.html.ep             ← action buttons (PROSPECT, VISIT MARKET)
  prospecting/
    fragment.html.ep             ← field scan panel with artifact detail
  market/
    fragment.html.ep             ← buyer negotiation card
  shed/
    fragment.html.ep             ← salvage ledger with sort/filter
  skills/
    fragment.html.ep             ← training records
  factions/
    fragment.html.ep             ← faction list with SVGs
  leaderboard/
    fragment.html.ep             ← ranked table
  sessions/
    new.html.ep                  ← terminal-form login
```

---

## Phase Dependencies

| Phase | Depends on | Description |
|-------|-----------|-------------|
| 0 | None | Amber CSS overlay is independent — can be done first |
| 1 | 0 | Fragment infrastructure requires shell placeholders from Phase 0 |
| 2 | 1 | Player fragment endpoint must exist (Phase 1) before game.js can use it |
| 3 | 1 | Same as Phase 2 |
| 4 | 1, 3 | Prospecting panel depends on fragment infra + instability meter component |
| 5 | 1, 3 | Market panel depends on fragment infra + shed offer buttons |
| 6 | 1 | Read-only panels depend only on fragment infra |
| 7 | 1, 4, 5 | Idle actions depend on prospecting/market fragment endpoints returning 204 |
| 8 | 0 | Login screen uses Phase 0 CSS classes, no fragment dependency |
| 9 | 2–8 | All panels must be converted before Bootstrap can be removed |

**Key constraint:** Phase 1 (backend) and Phase 2 (first frontend panel) can
overlap — implement the Player#show controller and `/player` route in Phase 1,
then immediately wire it into game.js in Phase 2 before building other resource
endpoints. The same applies to Phase 3 (Shed) following Phase 1's Shed work.

---

## Phase 0: Amber CSS Overlay

Add the terminal CSS design system **on top of Bootstrap** without removing
anything. The existing layout, template classes, and game.js all keep working.

**Files affected:**
- `public/css/app.css` (rewrite)
- `templates/layouts/default.html.ep` (edit — add normalize.css CDN link, Google Fonts link, CSRF meta tag)
- `templates/game/show.html.ep` (rewrite as shell)

**Tasks:**

1. Add normalize.css via `<link>` in `default.html.ep`.

2. Define CSS custom properties in `app.css` — the 16-color amber palette from
   `design_bible.md §6.1`.

3. Set up font stack via `<link>` to Google Fonts (IBM Plex Mono) in
   `default.html.ep`.

4. Create CSS component classes — component names per `design_bible.md §22`,
   CSS class names defined here rather than duplicating the bible's component
   list. Typical classes: `.mm-panel`, `.mm-btn`, `.mm-status`, `.mm-meter`,
   `.mm-ledger`, `.mm-badge`, `.mm-crier`, `.mm-form-input`, `.mm-icon`,
   `.mm-skeleton`.

5. Create CSS utility classes (`.mm-u-*`) as needed — limit to what panel
   migrations actually require.

6. Add placeholder `<div>`s to `templates/game/show.html.ep` with `id`
   attributes for each panel slot (e.g. `#slot-player`, `#slot-shed`).
   These are inert until each panel is migrated — the existing template
   literal render functions populate them via `innerHTML`.

7. Add skeleton CSS animation class for initial loading state.

8. Add CSRF token meta tag to shell.

**Explicitly NOT done in Phase 0:**
- Bootstrap CDN link is NOT removed.
- No template is rewritten to remove Bootstrap classes.
- The layout shell is NOT rewritten — existing Bootstrap layout continues.
- Hardware effects (scanlines, glow) are deferred to the final cleanup phase.

**Acceptance:** Game loads with dark amber background, monospace text,
Bootstrap styles still intact, game fully playable. Skeleton `<div>`s exist
in the DOM but are populated by existing template literals.

---

## Phase 1: Fragment Infrastructure (Backend-Only)

Add fragment routes, controllers, and templates alongside the existing
JSON endpoints and JS template literals. **game.js is not touched.**

**Files affected:**
- `lib/MagicMountain.pm` (register fragment MIME type, add resource routes)
- `lib/MagicMountain/Controller.pm` (add `_active_activity_type` helper)
- `lib/MagicMountain/Controller/Player.pm` (add `respond_to fragment` handler)
- `lib/MagicMountain/Controller/Season.pm` (create new controller)
- `lib/MagicMountain/Controller/Crier.pm` (create new controller)
- `lib/MagicMountain/Controller/Idle.pm` (create new controller)
- `lib/MagicMountain/Controller/Prospecting.pm` (add `show` action with fragment)
- `lib/MagicMountain/Controller/Market.pm` (add `show` action with fragment)
- `lib/MagicMountain/Controller/Shed.pm` (add `respond_to fragment` handler)
- `lib/MagicMountain/Controller/Skills.pm` (add `respond_to fragment` handler)
- `lib/MagicMountain/Controller/Factions.pm` (create new controller)
- `lib/MagicMountain/Controller/Leaderboard.pm` (add `respond_to fragment` handler)

**Tasks:**

1. In `MagicMountain.pm` startup, register fragment format:
   ```perl
   $self->types->type(fragment => 'text/html');
   ```

2. Add routes for resource endpoints (all under auth):
   ```perl
   $auth->get('/player')->to('player#show');
   $auth->get('/season')->to('season#show');
   $auth->get('/crier')->to('crier#show');
   $auth->get('/idle')->to('idle#show');
   $auth->get('/prospecting')->to('prospecting#show');
   $auth->get('/market')->to('market#show');
   $auth->get('/shed')->to('shed#show');
   $auth->get('/skills')->to('skills#show');
   $auth->get('/factions')->to('factions#show');
   $auth->get('/leaderboard')->to('leaderboard#show');
   ```

3. Add shared `_active_activity_type` helper to `Controller.pm`:
   ```perl
   sub _active_activity_type ($self, $char) {
       my $id = $char->getCol('pending_activity_id') or return undef;
       return 'prospecting' if $self->app->prospecting->get($id);
       return 'market'      if $self->app->market->get($id);
       return undef;
   }
   ```
   This avoids each Prospecting/Market `show` action loading both stores
   independently. The character model retains `pending_activity_id`; the
   helper resolves it to a type.

4. Each resource controller adds a `show` action with `respond_to`:

   **Player/Season/Crier/Shed/Skills/Factions/Leaderboard** — require character,
   load resource data, respond with JSON or fragment:
   ```perl
   sub show ($self) {
       my $char = $self->_require_character or return;
       # load resource-specific data
       $self->respond_to(
           json     => sub { $self->render(json => $data) },
           fragment => sub { $self->render('player/fragment') },
       );
   }
   ```

   **Season and Crier** do NOT require character — they use `current_player`
   and load season data directly, so they work even before a character exists:
   ```perl
   sub show ($self) {
       my $player_id = $self->session('playerId') or return $self->redirect_to('/login');
       my $season    = $self->app->active_season or return $self->rendered(204);
       $self->respond_to(
           json     => sub { $self->render(json => $data) },
           fragment => sub { $self->render('season/fragment') },
       );
   }
   ```

   **Prospecting/Market** — check activity type via helper, return 204 if
   no matching activity:
   ```perl
   sub show ($self) {
       my $char = $self->_require_character or return;
       my $type = $self->_active_activity_type($char);
       return $self->rendered(204) unless $type && $type eq 'prospecting';
       # load activity data
       $self->respond_to(
           json     => sub { $self->render(json => $data) },
           fragment => sub { $self->render('prospecting/fragment') },
       );
   }
   ```

   **Idle** — returns action buttons when both prospecting and market are
   idle. Checks activity type and renders idle panel:
   ```perl
   sub show ($self) {
       my $char = $self->_require_character or return;
       my $type = $self->_active_activity_type($char);
       return $self->rendered(204) if $type;  # not idle
       $self->respond_to(
           json     => sub { $self->render(json => { can_prospect => $char->getCol('action_points') >= 2 }) },
           fragment => sub { $self->render('idle/fragment') },
       );
   }
   ```

5. Action endpoints (POST /prospecting/push, etc.) add `refetch` to the
   existing response. The full `$result->{view}` is preserved so the
   simulation and existing code continue working:
   ```perl
   $self->render(json => {
       %{ $result->{view} },
       csrf_token => $self->csrf_token,
       refetch    => $self->_refetch_list($result),  # which resources changed
   });
   ```
   The `_refetch_list` helper returns a list of resource names affected by
   the action type (e.g., push → `['prospecting', 'player']`, offer →
   `['market', 'player', 'shed']`, skill purchase → `['skills', 'player']`).
   The frontend treats `refetch` as an opaque list — it re-fetches every
   name in the array.

   No fragment HTML in action responses. Frontend fetches updated resources
   via the `refetch` list.

6. The `game.js` rewrite happens incrementally in Phases 2–7 as each panel
   is converted from template literals to fragment fetching. Do NOT rewrite
   `game.js` in Phase 1 — only the backend fragment infrastructure is built
   here. The frontend integration pattern is described in the Architectural
   Change section above (Data Flow, Activity-aware loading order).

7. Create initial fragment templates for all resources (port current HTML from
   `game.js` template literals into `.ep` templates — visual polish later).

**Intermediate verification (within Phase 1):**

To reduce regression risk when touching 17+ files, implement in this order:

   a. Register MIME type and add all routes (file: `MagicMountain.pm`).
      Verify: `GET /player?_format=fragment` renders a fragment template.

   b. Implement any one resource controller completely (e.g., Player#show)
      plus its fragment template. Verify via browser or `prove -l t/`.

   c. Repeat for all resource controllers.

   d. Implement `_active_activity_type` and Prospecting/Market/Idle show
      actions with fragment templates.

   e. Verify full fragment flow by testing via the browser or a test script:
      each endpoint returns correct fragment HTML, action POST responses
      include `refetch` lists and `csrf_token`. Formal frontend integration
      (wiring `game.js` to use fragments) happens in Phases 2–7.

**Acceptance:** Full game loop works with no client-side HTML generation.
Each resource fetched independently. Action buttons work via delegation.
CSRF token flows correctly. POST response includes `refetch` list and
frontend re-fetches only affected resources. Errors in one fragment do
not affect others. Skeleton placeholders shown during initial load.

---

## Phase 2: Convert Player Panel


**Files affected:**
- `templates/player/fragment.html.ep` (create with `.mm-*` classes)
- `templates/season/fragment.html.ep` (create — used in status strip)
- `public/js/game.js` (update `render()` to fetch player fragment)
- `t/*` (update test assertions that check player HTML)

**Tasks:**

1. Create `templates/player/fragment.html.ep` — status strip layout per
   `design_bible.md §9.1` (DAY, AP, SCRAP, SCORE, season status). Component
   styling per `design_bible.md §22` (DeviceHeader, StatusStrip).

2. Create `templates/season/fragment.html.ep` — season day counter and
   active indicator per `design_bible.md §9.1`.

3. In `public/js/game.js`, update `render()` to fetch the player fragment:
   ```js
   async function renderPlayer() {
     const resp = await fetch('/player?_format=fragment');
     if (resp.status === 204) return;
     const html = await resp.text();
     document.getElementById('slot-player').innerHTML = html;
   }
   ```
   The `#slot-player` div already exists in the HTML shell (added in Phase 0).

4. Update test assertions that match player status strip HTML.

**Acceptance:** Player status strip renders via fragment. Stats update after
actions. Other panels still use template literals.

---

## Phase 3: Convert Shed Panel

**Files affected:**
- `templates/shed/fragment.html.ep` (create with `.mm-ledger` classes)
- `public/js/game.js` (swap `renderShed()` to fetch fragment)
- `lib/MagicMountain/Controller/Shed.pm` (add sort/filter via query params)
- `t/*`

**Tasks:**

1. Shed fragment template per `design_bible.md §16` (salvage ledger aesthetic).
2. Sort/filter controls via query params on the fragment endpoint.
3. Swap `renderShed()` in game.js to fetch `/shed?_format=fragment`.
4. Market offer buttons in shed rows: if market is active, render OFFER
   buttons with `data-item-id` attributes, wired via event delegation on
   `#slot-shed`.

**Acceptance:** Shed renders via fragment. Offer buttons work.

---

## Phase 4: Convert Prospecting Panel

**Files affected:**
- `templates/prospecting/fragment.html.ep` (field scan aesthetic)
- `templates/components/instability_meter.html.ep` (create — block-bar meter)
- `public/js/game.js` (swap `renderProspecting()` to fetch fragment)
- `public/js/game.js` (update `pushArtifact()` to read `refetch` for
  non-terminal results)
- `t/*`

**Tasks:**

1. Prospecting fragment — all UI elements (buttons, meters, tags, layout)
   per `design_bible.md §15`. No button details specified here; the design
   bible is the canonical spec.
2. Swap `renderProspecting()` to fetch `/prospecting?_format=fragment`.
3. Update `pushArtifact()`: for terminal results (collapse, breakthrough),
   call `loadGame()`. For non-terminal (pushed), read `refetch` from response
   and re-fetch only `prospecting` and `player` fragments.

**Acceptance:** Prospecting cycle works via fragments. Push updates inline.

---

## Phase 5: Convert Market Panel

**Files affected:**
- `templates/market/fragment.html.ep` (buyer negotiation card)
- `public/js/game.js` (swap `renderMarketVisit()` to fetch fragment)
- `public/js/game.js` (update `offerItem()`/`sendAway()`/`acceptCounter()`
  to use `refetch`)
- `t/*`

**Tasks:**

1. Market fragment — all UI elements (buyer card layout, faction icon,
   irritation meter, counter-offer UI, shed item offer buttons) per
   `design_bible.md §17`. See `docs/market_visit_ui_plan.md` for the
   detailed counter-offer and multi-item UI wiring plan — that plan's
   game.js changes are absorbed here.
2. Swap `renderMarketVisit()` to fetch `/market?_format=fragment`.
3. Update `offerItem()`: read `refetch` from response, re-fetch affected
   panels (`market`, `player`, `shed`).
4. Update `sendAway()` and `acceptCounter()` the same way.

**Acceptance:** Full market visit flow (begin, offer, counter, accept,
send away, storm off) works via fragments.

---

## Phase 6: Convert Crier, Skills, Factions, Leaderboard Panels

Each is a simple fragment swap — no action wiring needed.

**Files affected:**
- `templates/crier/fragment.html.ep`
- `templates/skills/fragment.html.ep`
- `templates/factions/fragment.html.ep` (include faction SVGs per design bible)
- `templates/leaderboard/fragment.html.ep`
- `templates/components/faction_icon.html.ep` (create — 5 inline SVGs)
- `public/js/game.js` (swap render functions to fetch fragments)
- `public/js/game.js` (update `purchaseSkill()` to use `refetch`)
- `t/*`

**Tasks:**

1. Create faction SVGs in `faction_icon.html.ep` (5 emblems per design bible).
2. Create all four fragment templates.
3. Swap render functions in game.js.
4. Update `purchaseSkill()` to use `refetch`.

**Acceptance:** All read-only panels render via fragments. Skill purchases
work and update player scrap inline.

---

## Phase 7: Convert Idle Actions + Navigation

**Files affected:**
- `templates/idle/fragment.html.ep` (action buttons)
- `public/js/game.js` (update action card logic to prefer idle fragment
  when no activity is active)
- `t/*`

**Tasks:**

1. Idle fragment with PROSPECT / VISIT MARKET buttons, server-rendered
   with `disabled` state based on AP.
2. Update action card logic: if both prospecting and market return 204,
   fetch `/idle?_format=fragment` for `#slot-action`.
3. All action buttons wired via event delegation on `#slot-action`.

**Acceptance:** Idle action buttons render via fragment.

---

## Phase 8: Login Screen Restyle

**Files affected:**
- `templates/sessions/new.html.ep` (rewrite)
- `public/css/app.css` (login-specific styles if needed)

**Tasks:**

1. Login form styled as terminal panel per `design_bible.md`.
2. Form input uses `.mm-form-input` styling.
3. Error messages inlined, amber/red styling.
4. This is standalone — no dependency on other phases.

**Acceptance:** Login screen has terminal aesthetic.

---

## Phase 9: Strip Bootstrap + Final Cleanup

At this point, every panel has been converted to fragments. The old template
literals are still in game.js but no longer called. Bootstrap CSS is still
loaded but nothing uses it visually.

**Files affected:**
- `templates/layouts/default.html.ep` (remove Bootstrap CDN link)
- `public/js/game.js` (delete old render functions + template literals)
- `t/*` (update remaining Bootstrap-class assertions to `.mm-*`)
- `public/css/app.css` (add hardware effects)

**Tasks:**

1. Remove Bootstrap `<link>` from `default.html.ep`.
2. Delete all template literal render functions from game.js:
   `renderRecap()`, `renderActionCard()`, `renderIdle()`, `renderProspecting()`,
   `renderMarketVisit()`, `renderShed()`, `renderSkills()`, `renderFactions()`,
   `renderLeaderboard()`, `updateStats()`, `wireActionButtons()`.
3. Delete old click handlers (`offerItem()`, `sendAway()`, `acceptCounter()`,
   `beginMarket()`, `beginProspecting()`, `pushArtifact()`, `stopProspecting()`,
   `purchaseSkill()`) — replace with a single delegated event listener on the
   action slot that dispatches by button ID and uses `refetch`.
4. Replace `render()` with a `Promise.allSettled` loop that fetches all
   fragment endpoints in parallel on page load.
5. Update remaining test assertions to match `.mm-*` classes.
6. Add hardware effects: scanline overlay, phosphor glow on hover,
   `prefers-reduced-motion` guard.

**Acceptance:** Zero Bootstrap classes in templates. Zero template literals
in game.js. All rendering via server fragments. Game fully playable.

---

## Verification

Each phase must pass the full test suite before being shipped:

```bash
prove -l t/
```

For phases 2-7 (panel conversions), only that panel's render function and
its tests change — the rest of the game is untouched. If a fragment endpoint
has a bug, only that one panel shows an error state.

Key test files for each panel conversion:

| Phase | Panel | Key test files |
|-------|-------|---------------|
| 2 | Player | `t/login.t`, `t/session.t` |
| 3 | Shed | `t/shed.t`, `t/shed_web.t` |
| 4 | Prospecting | `t/prospecting_web.t` |
| 5 | Market | `t/market_visit_web.t` |
| 6 | Crier/Skills/Factions/Leaderboard | `t/crier.t`, `t/skills_web.t`, `t/leaderboard.t`, `t/faction_state.t` |
| 7 | Idle | `t/prospecting_web.t`, `t/market_visit_web.t` |
| 9 | Bootstrap removal | All HTML-assertion tests listed above |

---

## Migration Concerns

- **Stale tabs**: If the user has two tabs open, an action in tab A doesn't
  update tab B. Future enhancement: a periodic polling mechanism or a
  visibility-change handler that re-fetches fragments on tab focus.

- **Action debouncing**: Rapid clicks on action buttons can fire multiple
  POST requests before the first response's fragment refetch completes. The
  frontend should disable the action button on click until the full cycle
  (POST + fragment refetches) finishes, or implement a request mutex per
  activity type.

- **`fetch` 204 edge case**: `fetch` resolves 204 successfully (no body),
  but `res.text()` returns empty string `""`, not `null`. The 204 check
  `res.status === 204 ? null : res.text()` correctly prevents injecting
  empty HTML. All fetch-call sites must preserve this pattern.

- **Session write contention during parallel GETs**: The `current_player`
  helper touches `$session->{last_active}` on every call. 9 parallel GET
  requests could race on session writes. With JSON persistence, each write
  rewrites the entire file. Consider making fragment GET endpoints skip the
  session touch (read-only session check) to reduce write contention.

- **Bootstrap removal gap**: Phase 9 (Bootstrap removal) is the only phase
  that touches test assertions across 7+ files simultaneously. Expect a
  spike in test failures during this phase. The cleanup is mechanical
  (`.card-*` → `.mm-panel`, `.btn` → `.mm-btn`, etc.) but thorough.
