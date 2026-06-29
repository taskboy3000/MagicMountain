# Plan: Panel-Nav Redesign

## Goal

Restructure the navigation so that the primary nav lives inside the primary
content panel and the secondary nav (ACCOUNT, orientation, mute) lives inside
the secondary panel. Both navs are driven by the same data structures and
rendering logic.

---

## Design Principles

- **Data-driven nav buttons** — Every button in both nav bars is an entry in a
  Perl data structure. Static HTML is eliminated.
- **Toggle as data** — The mute button is a tab with `type: toggle` and a
  `toggle_state` field, not a special `toggleMute()` JS function.
- **Testable backend** — Tab arrays built in `Navigation.pm`. Toggle state,
  active/inactive rules, and tab visibility testable in Perl.
- **Mechanical templates** — Containers only; populated by JS from JSON.
- **Nav never disappears** — Nav sits above the content area within each panel.
  Fragment fetches target `#primary-content` / `#secondary-content`, never the
  panel root, so the nav is never wiped.

---

## Changes (ordered for safe sequencing)

### 1. `lib/MagicMountain/Model/Character.pm` — New toggle column (FIRST)

Add `settings_muted` to column list and set a default in `create()`:

```perl
# columns
return [ @$cols, ..., 'settings_muted' ];

# create
$params{settings_muted} //= 0;
```

This must be done first — any code that calls `getCol('settings_muted')`
before the column exists will die with "assert: no such column".

### 2. `lib/MagicMountain/Service/Navigation.pm` — Restructure tab output

Return `primary_tabs` and `secondary_tabs` instead of `tabs`:

```perl
# Before
return { tabs => $tabs, ... };

# After
return {
    primary_tabs   => \@primary_tabs,
    secondary_tabs => \@secondary_tabs,
    ...
};
```

**Tab data structure** (each element):

```perl
{
    id      => 'home',          # unique tab identifier
    type    => 'nav',           # 'nav', 'toggle', or 'action'
    active  => 1,               # 1 = clickable, 0 = dimmed
    current => 1,               # 1 = currently selected view
    label   => 'HOME',          # display label

    # For nav-type tabs:
    fragment_url => '/home?_format=fragment',   # HTML fragment URL

    # For toggle-type tabs:
    toggle_state => 0,          # 0 = off (unmuted), 1 = on (muted)
    labels       => { on => '(((', off => ')))' },
    toggle_key   => 'mute',
    action_url   => '/nav/toggle',              # POST endpoint
    method       => 'POST',

    # For action-type tabs:
    fragment_url => '/orientation?_format=fragment',   # HTML fragment URL
    target       => 'primary-content',                 # content area ID

    # For inactive tabs:
    reason => 'Not enough AP',  # tooltip on hover
}
```

**Tab type semantics:**

| type | Click behavior | Examples |
|------|---------------|----------|
| `nav` | `applyNav(viewId)` — switches primary view | HOME, PROSPECT, BAZAAR, FACTIONS, CERTS |
| `toggle` | `handleAction(btn)` — POST to `action_url` | Mute |
| `action` | Fetch `fragment_url` into `target` | Orientation (?) |

**Tab distribution:**

| primary_tabs | secondary_tabs |
|---|---|
| home | account (type: nav, target: secondary-content) |
| prospect | orientation (type: action, target: primary-content) |
| bazaar | mute (type: toggle) |
| factions | |
| skills (CERTS) | |

**ACCOUNT** moves to secondary. Its click does NOT call `applyNav` — it
directly fetches `fragment_url` into `#secondary-content`. The primary
panel stays on whatever view it was showing. The secondary view mapping
(currently in Nav.pm) is not needed for ACCOUNT since its target is
explicit.

**Navigation.pm changes:**
- Remove ACCOUNT from `%BASE_TAB` (it no longer belongs in the primary tab
  permission system).

**Nav.pm changes:**
- Remove `account` from `%TAB_TO_VIEW` (account is no longer a primary view).
- The `/nav` endpoint returns `primary_tabs` and `secondary_tabs` instead
  of `tabs`.
- Add `POST /nav/toggle` endpoint: accepts `{ key: "mute" }`, flips the
  `settings_muted` column on the Character model, returns updated nav JSON.

**Toggle state persistence:**
- Stored as `settings_muted` on Character model (boolean 0/1).
- `/nav` reads it and includes as `toggle_state`.
- `POST /nav/toggle` flips it and returns updated nav.

### 3. `templates/game/show.html.ep` — Panel structure with nav

```html
<div id="main-area">
  <div id="panel-primary">
    <div id="primary-nav"></div>
    <div id="primary-content"></div>
  </div>
  <div id="panel-secondary">
    <div id="secondary-nav"></div>
    <div id="secondary-content"></div>
  </div>
</div>
```

Nav containers populated by JS from `/nav` JSON. Content containers are
where fragment fetches land.

### 4. `public/js/game.js` — Updated nav rendering and content targets

**All content insertion targets change** from `#panel-primary` /
`#panel-secondary` to `#primary-content` / `#secondary-content`:
- `loadGame()` lines 160, 168
- `applyNav()` lines 208, 209
- `fetchThenRender()` calls (lines 218-219)
- `.season-recap-link` handlers
- `[data-reference-id]` handlers
- All other references to `#panel-primary` / `#panel-secondary` for content

**Event delegation on panel content areas** moves from `#panel-primary` /
`#panel-secondary` to `#primary-content` / `#secondary-content` to avoid
double-dispatch when clicks bubble through nav bars.

**`renderNav` replaces `renderNavBar`:**

```javascript
function renderNav(tabs, containerId) {
  const bar = document.getElementById(containerId);
  bar.innerHTML = tabs.map(t => {
    let html = `<button class="nav-btn`;
    html += t.active ? ' active' : ' inactive';
    html += t.current ? ' current' : '';
    html += `" data-view="${t.id}"`;
    if (t.fragment_url) html += ` data-fragment-url="${t.fragment_url}"`;
    if (t.action_url)   html += ` data-action-url="${t.action_url}"`;
    if (t.method)       html += ` data-method="${t.method}"`;
    if (t.target)       html += ` data-target="${t.target}"`;
    if (t.toggle_key)   html += ` data-toggle="${t.toggle_key}"`;
    if (t.reason)       html += ` title="${t.reason}"`;
    html += `>`;
    html += t.label_live || t.label;
    html += `</button>`;
    return html;
  }).join('');
}
```

**Click delegation — three handlers, fully data-driven:**

```javascript
// Primary nav: nav-type tabs use applyNav, action/toggle use generic handlers
document.getElementById('primary-nav').addEventListener('click', e => {
  const btn = e.target.closest('[data-view]');
  if (!btn || btn.classList.contains('inactive')) return;
  e.stopPropagation();
  if (btn.dataset.actionUrl) { handleAction(btn); return; }
  if (btn.dataset.fragmentUrl) { handleFragmentFetch(btn); return; }
  applyNav(btn.dataset.view);
});

// Secondary nav: no applyNav — all buttons use fragment fetch or action
document.getElementById('secondary-nav').addEventListener('click', e => {
  const btn = e.target.closest('[data-view]');
  if (!btn || btn.classList.contains('inactive')) return;
  e.stopPropagation();
  if (btn.dataset.actionUrl) { handleAction(btn); return; }
  if (btn.dataset.fragmentUrl) { handleFragmentFetch(btn); return; }
});

// Generic fragment fetch: GET, HTML response, insert into target
function handleFragmentFetch(btn) {
  const url = btn.dataset.fragmentUrl;
  const target = btn.dataset.target || 'secondary-content';
  if (!url) return;
  fetch(url).then(r => r.text()).then(h => document.getElementById(target).innerHTML = h);
}
```

**Context bar** is set on every nav response:

```javascript
document.getElementById('context-bar').textContent = nav.context || '';
```

**Toggle side effect** (muting): `handleAction` already handles the POST.
After the call, the nav response includes `toggle_state`. The `applyNav`
callback mutes/unmutes audio based on the toggle state.

### 5. `public/css/app.css` — Updated layout

```css
#panel-primary {
  flex: 2;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  min-height: 0;
}
#primary-nav {
  display: flex;
  gap: 0.15rem;
  border-bottom: 1px solid var(--mm-border);
  padding: 0.3rem 0.4rem;
  flex-wrap: wrap;
  flex-shrink: 0;
}
#primary-content {
  flex: 1;
  overflow-y: auto;
  padding: 0.5rem 0.6rem;
}

#panel-secondary {
  flex: 1;
  display: flex;
  flex-direction: column;
  border-left: 1px solid var(--mm-border);
  overflow: hidden;
  min-height: 0;
}
#secondary-nav {
  display: flex;
  gap: 0.15rem;
  border-bottom: 1px solid var(--mm-border);
  padding: 0.3rem 0.4rem;
  flex-shrink: 0;
}
#secondary-content {
  flex: 1;
  overflow-y: auto;
  padding: 0.5rem 0.6rem;
}

/* Unregistered (login) state */
#device-frame.unregistered #panel-secondary { display: none; }
```

### 6. Dead code removal

After confirming new paths work:

| Location | Remove |
|---|---|
| `game.js` | `renderNavBar()` function |
| `game.js` | `toggleMute()`, `updateMuteButton()` functions |
| `game.js` | Old `#nav-bar` click delegation |
| `game.js` | Old `#panel-primary` / `#panel-secondary` event listeners |
| `show.html.ep` | Old `#nav-bar` div |
| `show.html.ep` | Old `.secondary-nav` with hardcoded `onclick` and mute button |
| `app.css` | Old `#nav-bar` rules |
| `app.css` | Old `.secondary-nav` rules |
| `app.css` | Old `#panel-primary` / `#panel-secondary` rules |
| `Navigation.pm` | ACCOUNT entry from `%BASE_TAB` |

### 7. Test updates

**`t/nav_web.t`:**
- Assert `primary_tabs` and `secondary_tabs` instead of `tabs`
- Add test for toggle: `POST /nav/toggle { key: "mute" }` flips state (include CSRF)
- Add test for secondary tab structure (ACCOUNT present, mute present, orientation present)
- Add test that primary tabs do NOT include ACCOUNT
- Existing tab activity/inactive tests keep same rules, just in different arrays

**`t/controller_web.t`:**
- Lines 162-164: update `->json_has('/tabs')` → `->json_has('/primary_tabs')`

**`t/result_web.t`:**
- Lines 146, 149: update `$json->{tabs}` → `$json->{primary_tabs}`

### 8. Walkthrough updates

**`bin/walkthrough`:**
- Line 177: `$nav->{tabs}` → `$nav->{primary_tabs}` (tab lookup for `click_tab`)
- Line 210: same
- Button finding and action still works via `data-action-url` on buttons — no structural changes needed for the action flow

---

## Verification

1. `prove -l t/nav_web.t t/controller_web.t t/result_web.t`
2. `bash bin/walkthrough`
3. `make indent && make clean`
4. `make cover && make report`
