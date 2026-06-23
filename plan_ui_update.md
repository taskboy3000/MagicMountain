# Magic Mountain UI Redesign Plan

Target: Amber ANSI terminal aesthetic via the ProspectBoy 3000, per `docs/design_bible.md`.

---

## Architectural Change: Server-Rendered Fragments

The core architectural shift: instead of building UI in JS template literals, the
server renders HTML fragments that JS fetches and inserts.

A `_render_fragments` helper in the base Controller renders each section template
to a string and returns a hashref. The `GET /game/fragments` route calls this and
renders it as JSON. Each write action (prospect, market, skills) also calls it to
return updated fragments in the response.

## Data Flow

```
Page load:
  GET /game (Accept: text/html)  →  empty shell with placeholder divs
  GET /game (Accept: html/fragment)  →  some HTML that can be inserted into the DOM
  JS inserts each fragment into its placeholder div

After action (e.g., POST /prospecting/push):
  Server does work, responds:
    HTML that can be inserted into the DOM
  JS swaps only the changed fragments

```


After any action, JS fetches a full refresh of all fragments:
```
  GET /game/  →  { fragments: { ... } }
```

### Template Tree

XXX - LLM FIX FRAGMENT TEMPLATES.  THESE GOES UNDER THE APPROPRIATE CONTROLLER FOLDER

```
templates/
  layouts/
    default.html.ep        ← stripped of Bootstrap, uses design-system.css
  components/
    faction_icon.html.ep   ← inline SVG, takes faction_id param
    artifact_icon.html.ep  ← inline SVG for category glyphs
    status_strip.html.ep   ← AP/scrap/score/season display
    terminal_panel.html.ep ← wrapper with title bar, content slot
    action_button.html.ep  ← styled button with optional AP cost
  game/
    show.html.ep           ← empty shell with placeholder divs, grid layout
    fragments/  # XXX THESE ARE IN THE WRONG PLACE
      header.html.ep       ← ProspectBoy 3000 title line
      player_stats.html.ep ← status strip numbers
      season_info.html.ep  ← day/total days
      crier.html.ep        ← bulletin feed
      action_card.html.ep  ← dispatches to idle/prospecting/market sub-template
      action_idle.html.ep
      action_prospecting.html.ep
      action_market.html.ep
      shed.html.ep         ← salvage ledger
      skills.html.ep       ← training records
      factions.html.ep     ← faction registry with icons
      leaderboard.html.ep  ← rankings snapshot
  sessions/
    new.html.ep            ← restyled login form
```

---

## Phase 0: CSS Design System + Layout

**Files affected:**
- `public/css/app.css` (rewrite)
- `templates/layouts/default.html.ep` (rewrite)
- `templates/game/show.html.ep` (rewrite as shell)

**Tasks:**

1. Define CSS custom properties in `app.css` — the 16-color amber palette from
   `design_bible.md §6.1`.

2. Set up font stack (IBM Plex Mono, etc.) via `@import` or `<link>`.

3. Create CSS component classes:

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
   | `.mm-btn--cost` | AP cost badge on button |
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

4. Build CSS grid layout in `show.html.ep`:
   ```
   ┌─────────────────────────────────────────────────────────┐
   │ mm-panel: header + status strip                         │
   ├────────────┬────────────────────────┬───────────────────┤
   │ mm-panel   │ mm-panel (main)        │ mm-panel          │
   │ Crier      │ Action Card            │ Shed Summary      │
   │            │                        │ Factions          │
   │            │                        │ Leaderboard       │
   ├────────────┴────────────────────────┴───────────────────┤
   │ season footer / instance info                            │
   └─────────────────────────────────────────────────────────┘
   ```
   - Desktop: 3 columns (1fr 2fr 1fr)
   - Tablet: 2 columns (left + center-right stack)
   - Mobile: single column, panels collapse vertically

5. Add subtle hardware effects class:
   - `::after` scanline overlay (`pointer-events: none`)
   - Optional: faint phosphor glow on `.mm-btn:hover`
   - `@media (prefers-reduced-motion: no-preference)` guard

6. Remove Bootstrap CDN link from `default.html.ep`. Remove all Bootstrap
   classes (`card`, `row`, `col-*`, `btn`, `badge`, etc.) from all templates.

**Acceptance:** Page loads with dark amber background, monospace text, no
Bootstrap styles visible.

---

## Phase 1: Fragment Rendering Infrastructure

**Files affected:**
- `lib/MagicMountain/Controller/Game.pm` (add fragment action)
- `lib/MagicMountain/Controller.pm` (add `_render_fragments` helper)
- `lib/MagicMountain/Controller/Prospecting.pm` (return fragments)
- `lib/MagicMountain/Controller/Market.pm` (return fragments)
- `lib/MagicMountain/Controller/Skills.pm` (return fragments)
- `lib/MagicMountain.pm` (add route for fragments)
- `public/js/game.js` (rewrite)
- `templates/game/fragments/*.html.ep` (create all fragment templates)

**Tasks:**

1. In `Controller.pm`, add `_render_fragments($c, $char, $season, ...)`:
   - Accepts the character and season models (already loaded by caller)
   - Loads needed data (shed items, skills, factions, leaderboard, crier)
   - Returns a hashref like:
     ```perl
     {
         header        => $c->render_to_string('game/fragments/header'),
         player_stats  => $c->render_to_string('game/fragments/player_stats'),
         season_info   => $c->render_to_string('game/fragments/season_info'),
         crier         => $c->render_to_string('game/fragments/crier'),
         action_card   => $c->render_to_string('game/fragments/action_card'),
         shed          => $c->render_to_string('game/fragments/shed'),
         skills        => $c->render_to_string('game/fragments/skills'),
         factions      => $c->render_to_string('game/fragments/factions'),
         leaderboard   => $c->render_to_string('game/fragments/leaderboard'),
     }
     ```
   - Each fragment template receives the data it needs via stash.
   - The `action_card` fragment echoes a sub-template based on current activity
     (idle/prospecting/market).

2. In `Game.pm`, add a `fragments` action:
   ```perl
   sub fragments ($self) {
       # ... load game state (same logic as show but lighter) ...
       $self->render(json => {
           ok        => 1,
           csrf_token => $self->csrf_token,
           fragments => $self->_render_fragments($char, $season, ...),
       });
   }
   ```

3. In `Prospecting.pm`, after each action returns from `dispatch`:
   - Load current state, call `_render_fragments`, append to the JSON response:
     ```perl
     $self->render(json => {
         %{ $result->{view} },   # ok, result, artifact, player
         fragments => $self->_render_fragments($char, $season, ...),
     });
     ```

4. Same pattern for `Market.pm` and `Skills.pm`.

5. Add route in `MagicMountain.pm`:
   ```perl
   $auth->get('/game/fragments')->to('game#fragments');
   ```

6. Rewrite `game.js`:
   - On load: fetch `/game/fragments`, insert each fragment by ID.
   - `render()` function: call `/game/fragments` and swap innerHTML for each
     section container.
   - After each action: the response already contains `fragments`; swap them
     without a separate fetch.
   - Wire `#btn-begin`, `#btn-push`, etc. via delegated event listeners on the
     action card container (since content is replaced).
   - Remove all HTML template literal functions (renderIdle, renderProspecting,
     renderMarketVisit, renderShed, renderSkills, etc.).

7. Create initial fragment templates for all sections (can be simple port of
   current HTML from `game.js` into `.ep` templates — visual polish comes later).

**Acceptance:** Full game loop works with no client-side HTML generation.
Action buttons work. Page refreshes correctly.

---

## Phase 2: ProspectBoy 3000 Header + Status Strip

**Files affected:**
- `templates/game/fragments/header.html.ep` (rewrite)
- `templates/game/fragments/player_stats.html.ep` (rewrite)
- `templates/game/fragments/season_info.html.ep` (rewrite)

**Tasks:**

1. `header.html.ep`:
   ```
   ┌──────────────────────────────────────────────────────────────┐
   │ THE PROSPECTBOY 3000 // LOCAL NODE 07                        │
   │ Personal Salvage Assistant                                   │
   ├──────────────────────────────────────────────────────────────┤
   ```
   - `.mm-panel` with top border accent
   - Box-drawing chars for flavor (sparing)
   - Device name from config (`$self->app->config->{ui}{terminal_name}`)

2. `player_stats.html.ep`:
   ```
   DAY 12/30   AP 5/15   SCRAP 184   SCORE 311
   ```
   - Horizontal status strip, each item: label + value
   - `.mm-status__item` styling

3. `season_info.html.ep`:
   Status badge: SEASON ACTIVE or NO SEASON, with color coding.

**Acceptance:** Header reads as the ProspectBoy 3000. Status strip shows live
data. Matches design bible §9.1 layout.

---

## Phase 3: Faction SVGs

**Files affected:**
- `templates/components/faction_icon.html.ep` (create)
- `templates/game/fragments/factions.html.ep` (rewrite)

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

3. Update `factions.html.ep` to replace star ratings with faction icon.

4. Optionally, create artifact category glyphs (3-4 common ones for MVP;
   expand later).

**Acceptance:** Five faction icons render at 24px, recognizable by shape alone.
Stars are gone.

---

## Phase 4: Prospecting Panel (Field Scan Aesthetic)

**Files affected:**
- `templates/game/fragments/action_prospecting.html.ep` (rewrite)
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
- `templates/game/fragments/action_market.html.ep` (rewrite)

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
- `templates/game/fragments/shed.html.ep` (rewrite)
- `lib/MagicMountain/Controller/Shed.pm` (update to return fragments)

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
5. Controls are server-side (submit sort/filter as params to `/shed`,
   returning HTML fragment).

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
Interactions (sort, filter, offer, upgrade) work through the new fragment flow.

---

## Phase 7: Idle Actions and Navigation

**Files affected:**
- `templates/game/fragments/action_idle.html.ep` (rewrite)

**Tasks:**

1. Per §10 of design bible, idle panel shows buttons:

   ```
   [ PROSPECT — 2 AP ]
   [ VISIT MARKET — 1 AP ]
   ```

2. Buttons disabled when AP insufficient. Show AP cost visually.
3. Future: navigation bar or action row (PROSPECT, SHED, BAZAAR, FACTIONS...)
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
- `templates/game/fragments/recap.html.ep` (create)

**Tasks:**

1. Season recap as archived business report per §20.
2. Style current recap display (currently Bootstrap card with warning header)
   as a terminal report panel.

---

## File Change Summary

| File | Action |
|------|--------|
| `public/css/app.css` | **Rewrite** — design system, remove Bootstrap overrides |
| `templates/layouts/default.html.ep` | **Rewrite** — remove Bootstrap, monospace font, scanline wrapper |
| `templates/game/show.html.ep` | **Rewrite** — CSS grid shell with placeholders, no Bootstrap |
| `templates/sessions/new.html.ep` | **Rewrite** — terminal login |
| `templates/components/faction_icon.html.ep` | **Create** — 5 faction SVGs |
| `templates/components/status_strip.html.ep` | **Create** — reusable status strip |
| `templates/components/instability_meter.html.ep` | **Create** — block-bar meter |
| `templates/components/terminal_panel.html.ep` | **Create** — panel wrapper |
| `templates/game/fragments/header.html.ep` | **Create** |
| `templates/game/fragments/player_stats.html.ep` | **Create** |
| `templates/game/fragments/season_info.html.ep` | **Create** |
| `templates/game/fragments/crier.html.ep` | **Create** |
| `templates/game/fragments/action_card.html.ep` | **Create** |
| `templates/game/fragments/action_idle.html.ep` | **Create** |
| `templates/game/fragments/action_prospecting.html.ep` | **Create** |
| `templates/game/fragments/action_market.html.ep` | **Create** |
| `templates/game/fragments/shed.html.ep` | **Create** |
| `templates/game/fragments/skills.html.ep` | **Create** |
| `templates/game/fragments/factions.html.ep` | **Create** |
| `templates/game/fragments/leaderboard.html.ep` | **Create** |
| `public/js/game.js` | **Rewrite** — fragment fetch/insert, delegated events |
| `lib/MagicMountain/Controller.pm` | **Edit** — add `_render_fragments` helper |
| `lib/MagicMountain/Controller/Game.pm` | **Edit** — add `fragments` action, use `_render_fragments` |
| `lib/MagicMountain/Controller/Prospecting.pm` | **Edit** — return fragments |
| `lib/MagicMountain/Controller/Market.pm` | **Edit** — return fragments |
| `lib/MagicMountain/Controller/Skills.pm` | **Edit** — return fragments |
| `lib/MagicMountain/Controller/Shed.pm` | **Edit** — return fragment on filter/sort |
| `lib/MagicMountain.pm` | **Edit** — add `/game/fragments` route |

---

## Verification

After each phase, run:
```bash
prove -l t/
```
All 253 tests must pass. If a test fails because of HTML structure changes
(e.g., a test checks for `.card` or `.btn` classes), update the test to match
the new CSS class names.

Some tests may need updating for the new fragment flow (e.g., tests that
check JSON response structure from action endpoints — the `fragments` key
is additive so existing checks should still work).

---

## Notes

- Each phase is designed to be independently testable.
- The fragment approach preserves the SPA-like feel (no full page reloads)
  while moving rendering to server-side templates.
- Faction SVGs are distributed as inline SVG in `faction_icon.html.ep`.
  No external image files needed.
- The 16-color palette ensures visual consistency. Do not add colors.
- Hardware effects in Phase 8 are optional and gated behind `prefers-reduced-motion`.
