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
    default.html.ep              ← terminal-style layout, no Bootstrap
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

## Phase 0: CSS Design System + Layout

**Files affected:**
- `public/css/normalize.css` (add via CDN link)
- `public/css/app.css` (rewrite)
- `templates/layouts/default.html.ep` (rewrite)
- `templates/game/show.html.ep` (rewrite as shell)

**Tasks:**

1. Add normalize.css via `<link>` in `default.html.ep` before `app.css`:
   ```html
   <link rel="stylesheet"
         href="https://cdn.jsdelivr.net/npm/normalize.css@8.0.1/normalize.min.css"
         integrity="sha256-+AJ2FMP9dN1qMfMwPjtGzI7JcG+0QCRnG4J4L+1j1c="
         crossorigin="anonymous">
   ```
   normalize.css normalizes browser rendering differences (margins, lists,
   form elements, print styles) without adding any visual styling. The amber
   terminal theme layers cleanly on top.

2. Define CSS custom properties in `app.css` — the 16-color amber palette from
   `design_bible.md §6.1`:
   ```css
   :root {
       --mm-amber:        #ffb000;
       --mm-amber-bright: #ffd040;
       --mm-amber-dim:    #805800;
       --mm-bg:           #1a0f00;
       --mm-bg-panel:     #2a1a00;
       --mm-bg-input:     #0d0800;
       --mm-text:         #ffc820;
       --mm-text-dim:     #a07000;
       --mm-border:       #4a3000;
       --mm-error:        #ff3030;
       --mm-success:      #40ff40;
       --mm-font:         'IBM Plex Mono', 'Courier New', monospace;
   }
   ```

3. Set up font stack via `<link>` to Google Fonts in `default.html.ep`.

4. Create CSS component classes:

   | Class | Purpose |
   |-------|---------|
   | `.mm-body` | body background, text color, font stack |
   | `.mm-grid` | 3-column dashboard grid |
   | `.mm-panel` | terminal-style panel (border, padding, bg) |
   | `.mm-panel-title` | panel header line |
   | `.mm-btn` | terminal-style button |
   | `.mm-btn:disabled` | disabled button state |
   | `.mm-btn--primary` | primary action button |
   | `.mm-btn--danger` | danger/destructive action |
   | `.mm-status` | horizontal status strip row |
   | `.mm-status__item` | individual stat with label + value |
   | `.mm-meter` | instability/condition progress bar |
   | `.mm-ledger` | table-like list for shed items |
   | `.mm-ledger__row` | row in ledger |
   | `.mm-badge` | terminal-style label/tag |
   | `.mm-crier` | Crier bulletin feed styling |
   | `.mm-form-input` | text input styled for terminal |
   | `.mm-icon` | 24x24 inline SVG container |
   | `.mm-icon--lg` | 48x48 icon |
   | `.mm-overlay-scanline` | subtle scanline pseudo-element |
   | `.mm-skeleton` | loading placeholder pulse animation |

5. Create CSS utility classes to replace Bootstrap's layout utilities:
   ```css
   .mm-u-text-center  { text-align: center; }
   .mm-u-text-dim     { color: var(--mm-text-dim); }
   .mm-u-text-error   { color: var(--mm-error); }
   .mm-u-mb-2         { margin-bottom: 0.5rem; }
   .mm-u-mb-3         { margin-bottom: 1rem; }
   .mm-u-mt-3         { margin-top: 1rem; }
   .mm-u-py-2         { padding-top: 0.5rem; padding-bottom: 0.5rem; }
   .mm-u-d-flex       { display: flex; }
   .mm-u-d-grid       { display: grid; }
   .mm-u-gap-2        { gap: 0.5rem; }
   .mm-u-gap-3        { gap: 1rem; }
   .mm-u-fs-3         { font-size: 1.75rem; }
   .mm-u-small        { font-size: 0.875em; }
   .mm-u-fw-bold      { font-weight: 700; }
   .mm-u-w-full       { width: 100%; }
   ```
   Only add utilities as needed when porting templates — do not recreate the
   entire Bootstrap utility library.

6. Build CSS grid layout in `show.html.ep`:
   ```
   ┌─────────────────────────────────────────────────────────┐
   │ mm-panel: header + status strip                         │
   ├────────────┬────────────────────────┬───────────────────┤
   │ mm-panel   │ mm-panel (main)        │ mm-panel          │
   │ Crier      │ Prospecting/Market     │ Shed              │
   │            │ (idle/prospecting/     │ Factions          │
   │            │  market)               │ Leaderboard       │
   ├────────────┴────────────────────────┴───────────────────┤
   │ season footer / instance info                            │
   └─────────────────────────────────────────────────────────┘
   ```
   - Desktop: 3 columns (1fr 2fr 1fr)
   - Tablet: 2 columns (left + center-right stack)
   - Mobile: single column, panels collapse vertically

7. Each placeholder div has an `id` matching its resource name, plus a CSS
   loading state while fragments are being fetched:
   ```html
   <div id="slot-player"    class="mm-panel mm-skeleton">…</div>
   <div id="slot-season"    class="mm-panel mm-skeleton">…</div>
   <div id="slot-crier"     class="mm-panel mm-skeleton">…</div>
   <div id="slot-action"    class="mm-panel mm-skeleton">…</div>
   <div id="slot-shed"      class="mm-panel mm-skeleton">…</div>
   <div id="slot-skills"    class="mm-panel mm-skeleton">…</div>
   <div id="slot-factions"  class="mm-panel mm-skeleton">…</div>
   <div id="slot-leaderboard" class="mm-panel mm-skeleton">…</div>
   ```
   ```css
   .mm-skeleton {
       opacity: 0.3;
       animation: mm-pulse 1.5s ease-in-out infinite;
   }
   @keyframes mm-pulse {
       0%, 100% { opacity: 0.3; }
       50%      { opacity: 0.6; }
   }
   ```
   When the fragment HTML is inserted via innerHTML, the skeleton class is
   replaced by the actual panel content.

8. Add CSRF token meta tag to shell:
   ```html
   <meta name="csrf-token" content="<%= $c->csrf_token %>">
   ```

9. Add subtle hardware effects class:
   - `::after` scanline overlay (`pointer-events: none`)
   - Optional: faint phosphor glow on `.mm-btn:hover`
   - `@media (prefers-reduced-motion: no-preference)` guard

10. Remove Bootstrap CDN link from `default.html.ep`. Remove all Bootstrap
    classes (`card`, `row`, `col-*`, `btn`, `badge`, etc.) from all templates.

**Acceptance:** Page loads with dark amber background, monospace text, no
Bootstrap styles visible, CSRF token embedded, empty shell rendered with
pulsing skeleton placeholders.

---

## Phase 1: Fragment Rendering Infrastructure

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
- `public/js/game.js` (rewrite — resource fetches, not template literals)
- `templates/*/fragment.html.ep` (create all fragment templates)

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

6. Rewrite `game.js`:
   - **Initialization order:**
     1. Shell page (`GET /game`) loads with skeleton placeholders and CSRF
        token in meta tag.
     2. Fire all fragment fetches in parallel using `Promise.allSettled` for
        per-resource error isolation:
        ```javascript
        const resources = ['player', 'season', 'crier',
                           'prospecting', 'market',
                           'shed', 'skills', 'factions', 'leaderboard'];
        const results = await Promise.allSettled(
            resources.map(r => fetch(`/${r}?_format=fragment`)                .then(res => res.status === 204 ? null : res.text())
                .catch(() => null))
        );
        resources.forEach((r, i) => {
            const slot = document.getElementById(`slot-${r}`);
            if (!slot) return;
            if (results[i].status === 'fulfilled' && results[i].value !== null) {
                slot.innerHTML = results[i].value;
                slot.classList.remove('mm-skeleton');
            } else if (r === 'prospecting' || r === 'market') {
                // 204 or error — handled by idle fetch below
            } else {
                slot.innerHTML = '<div class="mm-panel mm-panel--error">⚠ ERROR</div>';
                slot.classList.remove('mm-skeleton');
            }
        });
        ```
     3. If both `prospecting` and `market` returned 204/error, fetch idle:
        ```javascript
        if (!prospectingContent && !marketContent) {
            const idleHtml = await fetch('/idle?_format=fragment')
                .then(r => r.status === 204 ? null : r.text());
            if (idleHtml) {
                document.getElementById('slot-action').innerHTML = idleHtml;
                document.getElementById('slot-action').classList.remove('mm-skeleton');
            }
        }
        ```
   - **After each action (POST):**
     - Read `refetch` array from the JSON response.
     - For each resource name in `refetch`, fetch `/${name}?_format=fragment` and
       swap the matching slot's innerHTML.
   - **Event delegation:**
     ```javascript
     document.getElementById('slot-action').addEventListener('click', e => {
         const btn = e.target.closest('button');
         if (!btn) return;
         if (btn.matches('#btn-begin'))      beginProspecting();
         if (btn.matches('#btn-push'))       pushArtifact();
         if (btn.matches('#btn-stop'))       stopProspecting();
         if (btn.matches('#btn-visit-market')) beginMarket();
         if (btn.matches('#btn-offer'))      offerItem(btn.dataset.itemId);
         if (btn.matches('#btn-send-away'))  sendAway();
         if (btn.matches('#btn-accept'))     acceptCounter();
         if (btn.matches('#btn-decline'))    declineCounter();
     });
     ```
   - Remove all template literal render functions (`renderIdle`,
     `renderProspecting`, `renderMarketVisit`, `renderShed`, `renderSkills`,
     `renderFactions`, `renderLeaderboard`, `renderRecap`).
   - CSRF token extracted from meta tag on load, from POST responses after.

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

   e. Rewrite `game.js` last, after all fragment endpoints are individually
      verified. Test the full game loop.

**Acceptance:** Full game loop works with no client-side HTML generation.
Each resource fetched independently. Action buttons work via delegation.
CSRF token flows correctly. POST response includes `refetch` list and
frontend re-fetches only affected resources. Errors in one fragment do
not affect others. Skeleton placeholders shown during initial load.

---

## Phase 2: ProspectBoy 3000 Header + Status Strip

**Files affected:**
- `templates/player/fragment.html.ep` (rewrite)
- `templates/season/fragment.html.ep` (rewrite)

**Tasks:**

1. `player/fragment.html.ep`:
   ```
   ┌──────────────────────────────────────────────────────────────┐
   │ THE PROSPECTBOY 3000 // LOCAL NODE 07                        │
   │ Personal Salvage Assistant                                   │
   ├──────────────────────────────────────────────────────────────┤
   │ DAY 12/30   AP 5/15   SCRAP 184   SCORE 311                 │
   └──────────────────────────────────────────────────────────────┘
   ```
   - `.mm-panel` with top border accent
   - Box-drawing chars for flavor (sparing)
   - Device name from config (`$self->app->config->{ui}{terminal_name}`)
   - Horizontal status strip using `.mm-status` / `.mm-status__item`

2. `season/fragment.html.ep`:
   Status badge: SEASON ACTIVE or NO SEASON, with color coding.

**Acceptance:** Top panel reads as the ProspectBoy 3000. Status strip shows
live data. Matches design bible §9.1 layout.

---

## Phase 3: Faction SVGs

**Files affected:**
- `templates/components/faction_icon.html.ep` (create)
- `templates/factions/fragment.html.ep` (rewrite)

**Tasks:**

1. Create inline SVG for each faction (5 total):

   | Faction | Emblem concept | Shapes |
   |---------|---------------|--------|
   | Syndicate | Stacked offset crates with barcode | rectangles, line |
   | LibreMount | Open container under roof, outward arrows | path, polygon |
   | Faculty | Concentric rings with aperture and index ticks | circle, paths |
   | Purifiers | Warning triangle in broken containment ring | polygon, arc, line |
   | Revelationists | Split diamond with eye aperture, radiating ticks | polygon, paths |

   Each SVG:
   - `viewBox="0 0 128 128"`
   - `fill="currentColor"` (or `stroke="currentColor"`)
   - No text, no gradients, no raster
   - 1-2 colors max (secondary via `--mm-icon-accent` CSS var)
   - Readable at 24×24px
   - Consistent stroke width (~6px)

2. Template component `faction_icon.html.ep`:
   ```perl
   % my $faction_id = stash('faction_id');
   <svg class="mm-icon" viewBox="0 0 128 128" aria-label="<%= $faction_id %>">
   % if ($faction_id eq 'syndicate') {
     ... SVG paths for Syndicate ...
   % } elsif ...
   </svg>
   ```

3. Update `factions/fragment.html.ep` to use faction icons instead of star
   ratings.

4. Optionally, create artifact category glyphs (3-4 common ones for MVP;
   expand later).

**Acceptance:** Five faction icons render at 24px, recognizable by shape alone.
Stars are gone.

---

## Phase 4: Prospecting Panel (Field Scan Aesthetic)

**Files affected:**
- `templates/prospecting/fragment.html.ep` (rewrite)
- `templates/components/instability_meter.html.ep` (create)

**Tasks:**

1. Design prospecting panel per §15 of design bible:

   ```
   ┌─ MOUNTAIN INTAKE ───────────────────────────────┐
   │ Artifact: Warm Box With Too Many Latches         │
   │ Condition: STRAINED                              │
   │ Estimated Value: 42–57 scrap                     │
   │ Instability: ███████░░░                          │
   │ Classification: THERMAL / STORAGE / SUSPECT      │
   │                                                  │
   │ [ PUSH AGAIN ]  [ CASH OUT ]  [ DISCARD ]        │
   └──────────────────────────────────────────────────┘
   ```

2. Show two buttons: PUSH (primary, action) and STOP (warning, "cash out").
   If stop is not possible (collapse/stage), show appropriate message.

3. `instability_meter.html.ep`: visual bar using block characters or CSS
   progress bar with amber coloration.

4. Show collapse/breakthrough result messages inline (not as alert boxes).

**Acceptance:** Prospecting feels like a field scan intake. Push/stop cycle
works. Instability is visually clear.

---

## Phase 5: Market Visit Panel (Buyer Card)

**Files affected:**
- `templates/market/fragment.html.ep` (rewrite)

**Tasks:**

1. Market panel per §17 of design bible:

   ```
   ┌─ BAZAAR BUYER ROUTED ────────────────────────────┐
   │ FACTION: THE FACULTY          SIGNAL: PARTIAL     │
   │ BUYER: Archivist with sealed gloves               │
   │ TELL: Keeps asking whether it "records itself."   │
   │ PATIENCE: ███░░                                   │
   │                                                   │
   │ Offer an artifact from Shed.                      │
   └───────────────────────────────────────────────────┘
   ```

2. Faction icon displayed inline with faction name.
3. Patience meter using same block-bar style as instability meter.
4. Shed items listed with "OFFER" button per item (currently done in JS,
   move to template rendering).
5. Counter-offer flow: show counter value, ACCEPT / DECLINE buttons.
6. Sale result shown inline (message + new scrap total).

**Acceptance:** Market feels like a buyer negotiation session. All paths work:
match, settle, counter, reject, storm-off.

---

## Phase 6: Shed, Crier, Skills, Leaderboard

### Shed (Salvage Ledger)

**Files affected:**
- `templates/shed/fragment.html.ep` (rewrite)
- `lib/MagicMountain/Controller/Shed.pm` (update fragment handler)

**Tasks:**

1. Shed as ledger per §16:

   ```
   ┌─ SHED ────────────────────────────────────────────┐
   │ [sort: value∨] [filter: all∨]                     │
   │───────────────────────────────────────────────────│
   │ Warm Box          STR       38–52  day 3  ██░░    │
   │ Cold Resonator    FRESH    78–114  day 0  ░░░░    │
   │ Glowing Fragment  FADING   12–20   day 7  ████    │
   └───────────────────────────────────────────────────┘
   ```

2. Sort/filter controls using `.mm-form-input` styled selects/buttons.
3. Each row: artifact name, condition badge, value range, days in shed,
   decay urgency indicator.
4. If market is active, each row gets an OFFER button.
5. Sort/filter controls are driven by JS event handlers (not form submission):
   - `<select>` and `<button>` elements have `type="button"` attribute
     to prevent accidental form submission / page navigation.
   - JS click/change handlers call `fetch('/shed?_format=fragment&sort=value&order=asc')`
     and replace `#slot-shed` innerHTML with the response.
   - The Shed controller's `show` action reads sort/filter from query params
     and applies them via the existing `_apply_filters` helper.

### Crier (Bulletin Feed)

**Tasks:**
1. `.mm-crier` styling per §18 of design bible:

   ```
   ┌─ CRIER / BULLETIN ───────────────────────────────┐
   │ CRIER // MARKET BULLETIN                          │
   │ Too many warm boxes crossed the Bazaar.           │
   │─────────────────────────────────────────────────│
   │ CRIER // FACTIONS                                 │
   │ Syndicate buyers circling for signal devices.     │
   └──────────────────────────────────────────────────┘
   ```

### Skills (Training Records)

**Tasks:**
1. Per §20: training record style.

   ```
   ┌─ SKILLS / TRAINING ───────────────────────────────┐
   │ Prospecting II        ■■□□□  [ UPGRADE 30§ ]      │
   │ Upcycling I           ■□□□□  [ UPGRADE 20§ ]      │
   │ Selling III           ■■■■■  MAX                   │
   └──────────────────────────────────────────────────┘
   ```

### Leaderboard (Rankings Snapshot)

**Tasks:**
1. Compact table: rank, name, score. Terminal-style columns.

**Acceptance:** All panels display current data, styled consistently.
Interactions (sort, filter, offer, upgrade) work through the resource
fragment flow.

---

## Phase 7: Idle Actions and Navigation

**Files affected:**
- `templates/idle/fragment.html.ep` (rewrite)

**Tasks:**

1. The `/idle?_format=fragment` endpoint renders action buttons when no activity is
   active. Buttons are server-rendered with AP state baked in:

   ```
   [ PROSPECT — 2 AP ]
   [ VISIT MARKET — 1 AP ]
   ```

2. Buttons disabled when AP insufficient. The Idle controller checks
   `$char->getCol('action_points')` and sets `disabled` attribute on
   the button server-side. No client-side AP math needed.

3. Frontend orchestration handled in Phase 1: if both prospecting and
    market return 204, fetch `/idle?_format=fragment` to fill `#slot-action`.

4. Future: navigation bar or action row (PROSPECT, SHED, BAZAAR, FACTIONS...)
   as buttons along bottom per §9.1.

---

## Phase 8: Polish + Hardware Effects

**Files affected:**
- `public/css/app.css` (add effects)

**Tasks:**

1. Scanline overlay:
   ```css
   .mm-scanlines::after {
     content: '';
     position: fixed;
     inset: 0;
     pointer-events: none;
     background: repeating-linear-gradient(
       0deg,
       transparent,
       transparent 2px,
       rgba(0,0,0,0.03) 2px,
       rgba(0,0,0,0.03) 4px
     );
     z-index: 9999;
   }
   ```

2. Phosphor glow on hover:
   ```css
   .mm-btn:hover {
     text-shadow: 0 0 4px var(--mm-amber);
     box-shadow: 0 0 8px var(--mm-amber-dim);
   }
   ```

3. Subtle panel burn-in: faint repeated text ghost in panel backgrounds.

4. Brief settle animation after page load (CSS keyframe fade-in).

5. Focus states for keyboard navigation.

6. `prefers-reduced-motion` guard on all animations.

---

## Phase 9: Login Screen Restyle

**Files affected:**
- `templates/sessions/new.html.ep` (rewrite)
- `public/js/app.js` (if needed)

**Tasks:**

1. Login form styled as terminal panel:

   ```
   ┌─ PROSPECTBOY 3000 ───────────────────────────────┐
   │                                                   │
   │            MAGIC MOUNTAIN v1.0                    │
   │           PERSONAL SALVAGE ASSISTANT              │
   │                                                   │
   │  DISPLAY NAME: [________________]                 │
   │                                                   │
   │  [ ENTER THE MOUNTAIN ]                           │
   │                                                   │
   └───────────────────────────────────────────────────┘
   ```

2. Form input styled with terminal theme (amber border, dark bg).
3. Error messages inlined, amber/red styling.
4. No Bootstrap.

---

## Phase 10: Season Recap and Other Pages

**Files affected:**
- `templates/game/show.html.ep` (recap handling)

**Tasks:**

1. Season recap as archived business report per §20.
2. When no active season, `/season?_format=fragment` and `/player?_format=fragment` return
   recap HTML instead. Frontend renders in main slot.

---

## File Change Summary

| File | Action |
|------|--------|
| `public/css/normalize.css` | **Add** — CDN link in layout, or vendor locally |
| `public/css/app.css` | **Rewrite** — design system + utility classes, remove Bootstrap |
| `templates/layouts/default.html.ep` | **Rewrite** — remove Bootstrap, monospace font, scanline wrapper |
| `templates/game/show.html.ep` | **Rewrite** — CSS grid shell with skeleton placeholders |
| `templates/sessions/new.html.ep` | **Rewrite** — terminal login |
| `templates/components/faction_icon.html.ep` | **Create** — 5 faction SVGs |
| `templates/components/instability_meter.html.ep` | **Create** — block-bar meter |
| `templates/components/terminal_panel.html.ep` | **Create** — panel wrapper |
| `templates/player/fragment.html.ep` | **Create** |
| `templates/season/fragment.html.ep` | **Create** |
| `templates/crier/fragment.html.ep` | **Create** |
| `templates/idle/fragment.html.ep` | **Create** |
| `templates/prospecting/fragment.html.ep` | **Create** |
| `templates/market/fragment.html.ep` | **Create** |
| `templates/shed/fragment.html.ep` | **Create** |
| `templates/skills/fragment.html.ep` | **Create** |
| `templates/factions/fragment.html.ep` | **Create** |
| `templates/leaderboard/fragment.html.ep` | **Create** |
| `public/js/game.js` | **Rewrite** — resource fetch + Promise.allSettled + delegated events, no template literals |
| `lib/MagicMountain.pm` | **Edit** — register fragment MIME type, add resource routes |
| `lib/MagicMountain/Controller.pm` | **Edit** — add `_active_activity_type` helper |
| `lib/MagicMountain/Controller/Player.pm` | **Edit** — add `show` with `respond_to fragment` |
| `lib/MagicMountain/Controller/Season.pm` | **Create** (no `_require_character`) |
| `lib/MagicMountain/Controller/Crier.pm` | **Create** (no `_require_character`) |
| `lib/MagicMountain/Controller/Idle.pm` | **Create** |
| `lib/MagicMountain/Controller/Prospecting.pm` | **Edit** — add `show` action with fragment handler |
| `lib/MagicMountain/Controller/Market.pm` | **Edit** — add `show` action with fragment handler |
| `lib/MagicMountain/Controller/Shed.pm` | **Edit** — add `respond_to fragment` handler + sort/filter via query params |
| `lib/MagicMountain/Controller/Skills.pm` | **Edit** — add `respond_to fragment` handler |
| `lib/MagicMountain/Controller/Factions.pm` | **Create** |
| `lib/MagicMountain/Controller/Leaderboard.pm` | **Edit** — add `respond_to fragment` handler |

---

## Verification

After each phase, run:
```bash
prove -l t/
```
All tests must pass. After Phase 0 (Bootstrap removal), many tests will fail
because they check for `.card`, `.btn`, `.badge`, `.row`, `.col-*` classes
in rendered HTML (an estimated 20–40 assertions across the test suite).
Expect to update test assertions to match the new `.mm-*` class names.

After Phase 1 (fragment infra), tests that check the JSON response structure
of action endpoints should still pass because `$result->{view}` is piped
verbatim — only the `csrf_token` and `refetch` fields are added. No existing
JSON keys are removed.

Key test files affected by Bootstrap class changes:
- `t/prospecting_web.t` — checks for `.btn`, `.card` classes in rendered HTML
- `t/market_visit_web.t` — same
- `t/shed.t` — checks shed item listing HTML
- `t/session.t`, `t/login.t` — login form structure
- `t/crier.t`, `t/faction_state.t` — minimal HTML changes
- `t/leaderboard.t` — table structure
- `t/season_recap.t` — recap card classes

---

## Notes

- Each phase is designed to be independently testable.
- The resource-fragment approach preserves the SPA-like feel (no full page
  reloads) while moving rendering to server-side templates.
- Faction SVGs are distributed as inline SVG in `faction_icon.html.ep`.
  No external image files needed.
- The 16-color palette ensures visual consistency. Do not add colors.
- Hardware effects in Phase 8 are optional and gated behind `prefers-reduced-motion`.

### Missing Considerations (Deferred)

These were raised by the review but are outside the scope of the current plan.
They should be addressed before the UI rewrite is shipped to production:

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
  empty HTML, but this must be preserved in all fetch-call sites.

- **Phase 0 → Phase 1 transition breaks existing tests**: Phase 0 removes
  Bootstrap classes, which will cause test failures across at least 7 test
  files. These test updates are deferred to Phase 1 when the full fragment
  flow is in place.

- **Session write contention during parallel GETs**: The `current_player`
  helper touches `$session->{last_active}` on every call. 9 parallel GET
  requests could race on session writes. With JSON persistence, each write
  rewrites the entire file. Consider making fragment GET endpoints skip the
  session touch (read-only session check) to reduce write contention.
