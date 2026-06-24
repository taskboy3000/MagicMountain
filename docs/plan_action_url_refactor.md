# Plan: Backend-Driven Action URLs (Remove Game Logic from JS/Templates)

## Goal

Eliminate all hardcoded action URLs from **JS** and **fragment templates**. Game
logic (what actions are available, what URLs to call) lives entirely in the Perl
backend. Client code discovers actions at runtime via a uniform data structure.

## Design

Every view-state endpoint builds an `actions` array. One source of truth drives
both the JSON `_self.actions` block (for machine consumers) and the rendered
HTML (for the browser). A single reusable component renders action buttons in
all templates.

### Action Entry Format

```perl
{
  url      => '/prospecting/push',        # POST endpoint
  method   => 'POST',                     # HTTP method
  label    => 'Push',                     # Button text
  id       => 'btn-push',                # Optional DOM id
  class    => 'mm-btn-primary',          # Optional CSS class
  confirm  => 'Delete your account?',     # Optional confirm dialog text
  redirect => '/login',                  # Optional redirect on success (default: re-fetch /game)
  data     => { skill => 'prospecting' }, # Optional data-* attributes (sent as POST body)
}
```

Each key in `data => {}` becomes a `data-<key>` HTML attribute on the button.
Top-level keys (`id`, `class`, `confirm`, `redirect`) are HTML attributes, not
data attributes.

### Component

`templates/components/action_buttons.html.ep` — iterates `@actions` and renders
a `<button>` for each entry. All fragment templates that need action buttons
`include` this component.

### Nav Tab `action_url`

Each auto-begin tab (prospect, bazaar) carries an `action_url` in the nav
response when active and no activity is in progress (`!$type`). This logic
already exists in `_build_tabs` (the key is set on `$entry`) but was never
pushed into the returned tab hash — that's a one-line fix.

---

## Files to Change

### New Files
| File | Purpose |
|------|---------|
| `templates/components/action_buttons.html.ep` | Reusable action button renderer |

### Changed Files
| File | What Changes |
|------|--------------|
| `lib/MagicMountain/Controller/Nav.pm` | Add `action_url` to pushed tab hash (one-line fix). |
| `lib/MagicMountain/Controller/Prospecting.pm` | Build `actions` array (push, stop) in `show`; pass to stash and JSON `_self`. |
| `lib/MagicMountain/Controller/Market.pm` | Build `actions` array (send_away, accept_counter when pending) in `show`; pass to stash and JSON `_self`. |
| `lib/MagicMountain/Controller/Account.pm` | Build `actions` array (delete_account with confirm + redirect) in `show`; pass to stash and JSON `_self`. |
| `lib/MagicMountain/Controller/Skills.pm` | Build per-skill `actions` entries (purchase) in `index`; pass to stash and JSON `_self`. |
| `lib/MagicMountain/Controller/Idle.pm` | Add empty `_self.actions` to JSON for consistency. |
| `lib/MagicMountain/Controller/Shed.pm` | Accept `$market_active` param in `_item_view`; add `action_url`/`method` per item when market_active. |
| `templates/prospecting/scan.html.ep` | Replace hardcoded push/stop buttons with `include 'components/action_buttons'`. |
| `templates/market/negotiation.html.ep` | Replace hardcoded send_away/accept_counter buttons with component. |
| `templates/shed/ledger.html.ep` | Replace hardcoded offer button on each row with component (single-item action per row). |
| `templates/account/settings.html.ep` | Replace hardcoded delete button with component. |
| `templates/skills/training.html.ep` | Replace hardcoded purchase buttons with component. |
| `templates/idle/actions.html.ep` | No change (no action buttons in idle fragment). |
| `public/js/game.js` | Add generic `data-confirm` and `data-redirect` handling in `handleAction`. Remove delete-account special case. |
| `GAME_ARCHITECTURE.md` | Add section documenting the `_self.actions` convention. |

### Walkthrough
| File | What Changes |
|------|--------------|
| `bin/walkthrough` | `click_tab` reads `action_url` from nav tabs. Activity driving stays with HTML `data-action-url` discovery (tests the full rendering pipeline). |

### Tests
| File | What Changes |
|------|--------------|
| `t/nav_web.t` | Assert `action_url` present on prospect/bazaar tabs when conditions allow, absent otherwise. |
| `t/controller_web.t` or new test | Assert `_self.actions` shape on prospecting, market, account, skills, idle, shed JSON endpoints. |

---

## Implementation Order

1. **Create `templates/components/action_buttons.html.ep`** — the shared renderer.
2. **Fix `Nav.pm`** — add `action_url` to pushed tab hash (one line).
3. **Refactor each controller `show()`/`index()`** — build `actions` array, pass to stash + JSON `_self`.
4. **Fix `Shed.pm` `_item_view`** — accept `$market_active`, add `action_url`/`method`.
5. **Update each fragment template** — replace hardcoded buttons with `include`.
6. **Update `game.js`** — add `data-confirm` + `data-redirect` in `handleAction`, remove delete-account special case.
7. **Update `GAME_ARCHITECTURE.md`** — document the convention.
8. **Update `bin/walkthrough`** — nav-driven tab clicks, keep HTML action discovery.
9. **Run tests + walkthrough** — confirm full loop.

---

## Verification

- `prove -l t/` — all 400+ tests pass
- `MM_TEST_PORT=99XX perl bin/walkthrough` — full game loop via nav-driven actions
- `node -c public/js/game.js` — JS syntax valid
- `perl -Ilib -c lib/MagicMountain/Controller/Nav.pm` — Perl syntax valid
