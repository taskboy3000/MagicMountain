# Plan: CSS Architecture Refactor

## Scope
- 89 inline `style=` across 20 template files → reduce to ~20 (only data-driven ones)
- 60 existing `mm-*` CSS classes → extend with missing utilities and define 5 orphan classes
- Only 3 `<h*>` tags currently exist → convert all `.mm-panel-header` divs to semantic `<h2>`/`<h3>`
- Fix typo `.text-rigth` → `.text-right`

---

## Phase 1: Utility classes + typo fix

**File:** `public/css/app.css` — add these new classes:

| Class | CSS | Replaces (count) |
|-------|-----|-----------------|
| `.mm-text-sm` | `font-size: 0.78rem` | 13 inlines |
| `.mm-text-xs` | `font-size: 0.72rem` | 4 inlines |
| `.mm-text-2xs` | `font-size: 0.7rem` | ~4 inlines |
| `.mm-text-3xs` | `font-size: 0.65rem` | 2 inlines |
| `.mm-clickable` | `cursor: pointer` | 6 inlines |
| `.mm-py-xs` | `padding-top: 0.2rem; padding-bottom: 0.2rem` | 8 inlines (broker data cells) |
| `.mm-mt-sm` | `margin-top: 0.5rem` | 5 inlines |
| `.mm-mb-sm` | `margin-bottom: 0.5rem` | 5 inlines |
| `.mm-gap` | `gap: 0.5rem` | 4x `gap:0.5rem;margin-top:0.5rem` combos |
| `.mm-pre` | `white-space: pre-wrap; word-wrap: break-word` | 2 inlines (recap narrative) |
| `.mm-flex-1` | `flex: 1` | 2 inlines (negotiation) |

Also rename `.text-rigth` → `.text-right`. Keep `.text-rigth` as an alias pointing to `.text-right` rules for safety.

**Template changes:** Replace the 13 `font-size: 0.78rem` inlines with `class="mm-text-sm"`. Replace `cursor:pointer` inlines with `.mm-clickable`. Replace other repeated patterns with utility classes.

---

## Phase 2: Semantic headings

### Mapping

| Current | New tag | CSS class | Files affected |
|---------|---------|-----------|----------------|
| `<div class="mm-panel-header">` | `<h2>` | `.mm-panel-header` (unchanged CSS) | 20 files, 22 instances |
| `<div class="mm-display-label">` | `<h3>` | `.mm-display-label` (unchanged CSS) | ~3 files (advisories, shed) |
| `<h2 class="mm-panel-header">` | no change | — | dashboard (already correct) |
| `<h3>` (PROSPECT REPORT, FACTION MARKET) | no change | — | climate_card, dashboard |

### Files with `.mm-panel-header` div (complete list)

- `templates/account/settings.html.ep` (2 instances)
- `templates/black_market/broker.html.ep`
- `templates/components/salvage_ledger.html.ep`
- `templates/crier/bulletin.html.ep`
- `templates/game/device_frame.html.ep`
- `templates/idle/actions.html.ep`
- `templates/leaderboard/rankings.html.ep`
- `templates/market/negotiation.html.ep`
- `templates/onboarding/notice.html.ep`
- `templates/orientation/show.html.ep`
- `templates/player/status.html.ep`
- `templates/prospecting/scan.html.ep`
- `templates/pvp/panel.html.ep` (2 instances)
- `templates/reference/show.html.ep`
- `templates/result/show.html.ep`
- `templates/season/recap.html.ep`
- `templates/sessions/credentials.html.ep`
- `templates/sessions/recovery_form.html.ep`
- `templates/sessions/token_prompt.html.ep`
- `templates/skills/training.html.ep`

### No CSS changes needed
Existing `.mm-panel-header` and `.mm-display-label` rules have higher specificity than `h2`/`h3` base styles, so no visual regression.

No CSS changes needed — existing `.mm-panel-header` and `.mm-display-label` rules have higher specificity than `h2`/`h3` base styles.

### Motivation
- Screen reader hierarchy
- Document outline
- Consistent with the 3 existing `<h*>` tags

---

## Phase 3: Pattern classes for top-offending files

Three files account for 32 of 89 inlines:

### `templates/black_market/broker.html.ep` (14 inlines)
- 8x `padding:0.2rem 0` with `text-align:right` → `.mm-py-xs.text-right`
- 2x `margin:0.5rem 0` → `.mm-mt-sm.mm-mb-sm`
- 2x inline-flex containers with gap → add `.mm-inline-flex` utility or keep as inline if wrapper-specific
- 1x `font-size:0.72rem` → `.mm-text-xs`

### `templates/market/negotiation.html.ep` (10 inlines)
- 3x `font-size:0.78rem` → `.mm-text-sm` (Phase 1)
- 2x `gap:0.5rem;margin-top:0.5rem` → `.mm-gap.mm-mt-sm`
- 2x `flex:1` → `.mm-flex-1`
- 1x `align-items:center` → `.mm-items-center` utility (new)
- 1x `flex:1;max-width:...` → keep inline (value-specific)

### `templates/pvp/panel.html.ep` (8 inlines)
- `.mm-info-row`, `.mm-subhead`, `.mm-data-row` already exist — several inlines just redundant
- 2x `margin:0.3rem 0;display:flex` → `.mm-info-row` (already has these)
- 1x `font-size:0.65rem` → `.mm-text-3xs`

### `templates/season/recap.html.ep` (7 inlines)
- 2x narrative blocks (`white-space:pre-wrap;...`) → `.mm-pre`
- 2x `margin:0 0 0.75rem 0` → `.mm-mb-sm`
- 1x `font-size:1.1rem;margin:0 0 0.5rem 0;letter-spacing:0.1em` → keep inline (unique combination)

---

## Phase 4: Orphan classes (used in templates, no CSS definition)

| Class | Used in | Action |
|-------|---------|--------|
| `.mm-npc-badge` | `templates/leaderboard/rankings.html.ep:11` | Add CSS: border + color similar to `.mm-badge` but distinct tint |
| `.mm-btn-disabled` | `templates/components/salvage_ledger.html.ep:44` | Template uses `<button class="mm-btn mm-btn-disabled"` but **lacks the `disabled` attribute**. `.mm-btn-disabled` has no CSS definition so it has no visual effect. Fix: add `disabled` attribute and remove `.mm-btn-disabled` class (`.mm-btn:disabled` pseudo-class will handle it). |
| `.offer-btn` | `salvage_ledger.html.ep:46` + `t/fragment_web.t` | **Must keep class name** — tests assert `qr{offer-btn}`. Add CSS: `.offer-btn` inherits from `.mm-btn`, adds amber border (same as `.mm-btn-primary`). |
| `.buy-skill-btn` | `skills/training.html.ep:23` + `Controller/Skills.pm:20` | Add CSS: skill purchase button style. Note: template uses `mm-btn mm-btn-primary mm-btn-upgrade buy-skill-btn` but Controller omits `mm-btn-upgrade`. `.buy-skill-btn` CSS should work with or without `mm-btn-upgrade`. |
| `.season-recap-link` | `settings.html.ep:19,22` + `game.js` (event delegation target) | Add CSS: cursor pointer + underline (currently inline). JS depends on class name — must keep it. |

---

## Phase 5: Inline styles that stay (data-driven)

~18 inlines are legitimately dynamic and must remain inline:

- `grid-template-rows: repeat(<%= $mh %>, 1fr)` — mountain chart
- `grid-row: <%= $i + 1 %>` — mountain chart row positioning
- `background:<%= $bar{$item->{condition}} // 'var(--mm-green)' %>` — condition color bar in salvage ledger
- `style="<%= $s->{view} ? 'cursor:pointer' : '' %>"` — advisories conditional cursor
- `style="flex:<%= $can_continue ? '0.5' : '1' %>"` — result screen dynamic flex
- `style="color:var(--mm-bg);background:var(--mm-text);font-size:0.72rem;..."` — device frame status bar (one-off)
- `style="grid-template-columns:1fr auto"` — mountain chart body
- `style="min-width:8rem;text-align:right"` — skills training cost column (unique)

These stay as-is. No changes needed.

---

## Files changed (summary)

| File | Phase | Change |
|------|-------|--------|
| `public/css/app.css` | 1, 4 | Add ~12 utility classes, 5 orphan class definitions, fix typo |
| `templates/black_market/broker.html.ep` | 1, 2, 3 | 14 inlines → classes; heading → `<h2>` |
| `templates/market/negotiation.html.ep` | 1, 2, 3 | 10 inlines → classes; heading → `<h2>` |
| `templates/pvp/panel.html.ep` | 2, 3 | 8 inlines → classes; 2 headings → `<h2>` |
| `templates/season/recap.html.ep` | 2, 3 | 7 inlines → classes; heading → `<h2>` |
| `templates/home/dashboard.html.ep` | 1, 2 | Inlines → classes; headings semantic |
| `templates/components/salvage_ledger.html.ep` | 2, 4 | Add `disabled` attr, keep `.offer-btn` class; heading → `<h2>` |
| `templates/prospecting/scan.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/sessions/credentials.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/sessions/recovery_form.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/sessions/token_prompt.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/skills/training.html.ep` | 2, 4 | Inlines → classes; headings semantic |
| `templates/result/show.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/account/settings.html.ep` | 2, 4 | `.season-recap-link` gets CSS, remove inline styles; 2 headings → `<h2>` |
| `templates/leaderboard/rankings.html.ep` | 2, 4 | `.mm-npc-badge` gets CSS; heading → `<h2>` |
| `templates/idle/actions.html.ep` | 1, 2 | Inline → class; heading → `<h2>` |
| `templates/orientation/show.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/reference/show.html.ep` | 1, 2 | Inlines → classes; heading → `<h2>` |
| `templates/game/device_frame.html.ep` | 2 | Heading → `<h2>`; inline status bar stays (one-off) |
| `templates/onboarding/notice.html.ep` | 2 | Heading → `<h2>`; inline button stays (unique) |
| `templates/crier/bulletin.html.ep` | 2 | Heading → `<h2>` |
| `templates/player/status.html.ep` | 2 | Heading → `<h2>` |

--- Not touched (keep all inline):
| `templates/factions/mountain_chart.html.ep` | 5 | Dynamic grid values (data-driven) |
| `templates/layouts/default.html.ep` | 5 | Unique GitHub link styling |

---

## Verification

After each phase:
- `make ci-check` — all 65 test files must pass
- `perl bin/walkthrough` — 32/32 steps must pass (especially after Phase 2 which affects all routes)
- Visual check: no visual regression from class migrations
- `.text-rigth` → `.text-right`: confirm zero template references to `.text-rigth` before renaming
- [x] Architecture review complete
- [x] Implementation review complete
