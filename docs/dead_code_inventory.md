# Dead Code Inventory — Post-Redesign Cleanup

## Removed in this implementation

These were already removed during the redesign phases:

| What | Where | Phase |
|------|-------|-------|
| Slot containers (`#slot-player`, `#slot-action`, `#slot-crier`, `#slot-shed`, `#slot-skills`, `#slot-factions`, `#slot-leaderboard`, `#slot-recap`) | `templates/game/show.html.ep` | 3 |
| Legacy shell (`#legacy-shell`) | `templates/game/show.html.ep` | 3 |
| `renderActionFragment()` | `public/js/game.js` | 2 |
| `renderProspectingFragment()` | `public/js/game.js` | 2 |
| `renderMarketFragment()` | `public/js/game.js` | 2 |
| `refetchFragments()` | `public/js/game.js` | 2 |
| `renderRecap()` | `public/js/game.js` | 2 |
| `renderPlayerFragment()` | `public/js/game.js` | 2 |
| `renderShedFragment()`, `renderCrierFragment()`, `renderSkillsFragment()`, `renderFactionsFragment()`, `renderLeaderboardFragment()` | `public/js/game.js` | 2 |
| All `Object.assign(G.player, ...)` calls | `public/js/game.js` action handlers | 2 |
| All `G.prospecting` / `G.market_visit` writes | `public/js/game.js` action handlers | 2 |
| `updateStats()`, `renderActionCard()`, `renderIdle()`, `wireActionButtons()` | `public/js/game.js` | 2 |
| `%REFETCH` hash | `lib/MagicMountain/Controller.pm` | 4 |
| `refetch` key in `_render_action` response | `lib/MagicMountain/Controller.pm` | 4 |
| AP/SCORE/SCRAP from player/status fragment | `templates/player/status.html.ep` | 4 |

## Safe to remove (not yet deleted)

These are no longer referenced or needed but still exist in the codebase:

### CSS classes (in `public/css/app.css`)
- `.mm-status`, `.mm-status-item`, `.mm-status-label`, `.mm-status-value` — replaced by `#status-strip`
- `.mm-meter`, `.mm-meter-bar`, `.mm-meter-bar.filled`, `.mm-meter-bar.danger` — instability meter was removed earlier
- `.card`, `.card-header`, `.card-body`, `.text-muted`, `.btn-success`, `.btn-primary`, `.btn-warning`, `.btn-info`, `.btn-outline-secondary`, `.btn-outline-danger`, `.alert-secondary`, `.badge.bg-*`, `.faction-stars` — Bootstrap override classes (Bootstrap was removed but these CSS classes remain as dead rules)

### Controllers
- `GET /season` → `Controller/Season.pm` — route is commented out. Controller code is preserved for potential re-enable.
- `GET /leaderboard/factions` → `Leaderboard#factions` — kept per user request, but no frontend code calls it.

### Test assertions
- `t/fragment_web.t`: season fragment subtest is commented out (matching the commented-out route).

## Not dead (confirmed still in use)

- `GET /game` → `Game#show` — called by `loadGame()` for boot state
- `GET /nav` → `Nav#show` — NEW, called by `applyNav()` after every action
- All POST action endpoints — still called by action handlers
- All fragment GET endpoints — still called via `/nav`-provided fragment URLs
- `t/nav_web.t` — NEW, 8 tests covering nav states
