# Futures — Magic Mountain

Unfinished business and planned work beyond the current MVP.

---

## MVP Categorization

See `AGENTS.md` for current implementation status.

| Category | Items |
|----------|-------|
| **Defer Past MVP** | MariaDB Migration, Market Dynamics (§6.7), Commission System (§7.3), MarketVisit Enhancements, Rate limiting / HTTPS / Password auth |

### Defer Past MVP

| Item | Effort | Why |
|------|--------|-----|
| MariaDB Migration | High | JSON works for single-server; arch doc says post-MVP (§18.2) |
| Market Dynamics (§6.7) | High | Explicitly "not required for initial implementation" |
| Commission System (§7.3) | Medium | Requires data model + MarketVisit changes; post-MVP feature |
| MarketVisit Enhancements (§6.5) | Low-Med | Basic one-shot flow works; multi-item/counter-offer is polish |
| Rate limiting / HTTPS / Password auth | Low | Fine for alpha; deferred per AGENTS.md |

---

## CSRF Protection — DONE

Session-based CSRF token returned on login, sent as `X-CSRF-Token` header
on all authenticated write requests. Login and logout routes are exempt.
See `lib/MagicMountain.pm` (`csrf_token` helper + `$auth_write` bridge),
`public/js/game.js` (client-side header injection).

## Eliminate Direct JSON I/O in Tests — DONE

All 12 test files have been fixed. Zero `write_file(*.json)` calls remain
in the test suite. Tests now seed state exclusively through Model objects
(`->create`, `->save`), keeping them portable across persistence backends.

---

## MariaDB Migration

JSON file persistence is the primary bottleneck for large-scale simulation
and concurrent play. Each `save()` writes the entire table to disk; at 50
bots × 30 days, a single simulation run takes ~3 hours.

**Target**: Replace `MagicMountain::Model` file I/O with DBIx::Class or
similar ORM behind the same `getCol`/`setCol`/`save`/`find` API surface.
The model, activity, and controller code should require minimal changes.

**Reference**: GAME_ARCHITECTURE.md §18.2

---

## Season Finalization UI — DONE

Web button on the game page (`POST /season/end`) calls the same
`Season::finalize` method as the CLI command. Season labeling now shows
in the UI (e.g. "Season 1 — Day 5 of 30").

---

## Crier Narrative Expansion — DONE

Daily maintenance messages (surge, slump, dominance, milestone, season
opening, daily progress) were already implemented in `crier.yml`. Added:
`content/text/negotiation_reactions.yml` with per-faction flavor text for
all offer outcomes (match, settle, mismatch, storm_off), replacing hardcoded
sprintf messages in MarketVisit. `content/text/commission_triggers.yml`
created as content-only (unused until Commission System is built).

---

## Faction Snapshot History — DONE

Daily faction influence snapshots persisted in a new `FactionSnapshot` model,
written during daily maintenance (after Crier, before transcript) and at
season finalization. Season recap highlights now include `top_faction`,
`top_faction_influence`, and `factions_competing`. Leaderboard exposes a
`GET /leaderboard/factions` endpoint returning per-faction time series.

---

## Commission System (§7.3)

After a player's second sale to a faction, that faction may issue a
commission — a standing offer for specific artifact traits at a premium.
The data model (standing, faction_sales) is in place. The trigger logic,
commission storage, premium application in MarketVisit, and expiry through
prospecting attempts are not yet implemented.

---

## MarketVisit Enhancements (§6.5)

Counter-offers and multi-item visits are not yet implemented. The current
implementation is one-shot: match → sale, mismatch → settle or irritation
→ try another item or storm off.

---

## Market Dynamics (§6.7)

Supply/demand, faction appetite caps, trait saturation, and the
Desperate Recruiter rubber-banding mechanic. All planned but deferred
past MVP.

---

## Rate Limiting — Plan

**Priority: P0 (before real users)**

The login endpoint (`POST /sessions`) has no brute-force protection. Since
accounts are auto-created on first login (name-only auth), an attacker can
enumerate existing usernames and spam login requests. Even without passwords,
rate limiting is the only defense against account enumeration and session
table flooding.

### Approach

In-memory IP-based rate limiter implemented as a Mojo `under` bridge between
the maintenance gate and the login route. Clean, self-contained, zero
dependencies.

### Design

**Storage**: A plain Perl hash (`%attempts`) keyed by client IP. Each entry
holds `{ count => N, first_attempt => timestamp, blocked_until => timestamp }`.
Entries are cleaned up lazily — expired records are removed on access.

**Location**: `MagicMountain::RateLimiter` — a new class with `check($ip)`
and `record_failure($ip)` / `record_success($ip)` methods. A `cleanup` method
periodically prunes expired entries.

**Configuration** (in `magic_mountain.yml`, defaults in `defaultConfig`):

```yaml
rate_limit_max_attempts: 5       # failed attempts before block
rate_limit_window_minutes: 15   # sliding window for counting attempts
rate_limit_block_minutes: 15    # how long the block lasts
rate_limit_cleanup_interval: 300 # seconds between stale-entry cleanup
```

**Route integration** (in `MagicMountain.pm::buildRoutes`):

1. A new `under` bridge wraps the login route, after the maintenance gate:
   ```
   $no_maintenance
     → rate_limit_check (new)
       → $no_maintenance->post('/sessions')
   ```

2. The bridge calls `$self->app->rate_limiter->check($ip)`; if blocked,
   renders `{ ok => 0, error => 'Too many attempts' }` with 429 status
   and returns undef.

3. The controller (`Sessions::create`) calls
   `$self->app->rate_limiter->record_failure($ip)` on any non-success
   response, or `record_success($ip)` on login success.

**Client IP resolution**: `$c->tx->remote_address` for direct connections,
with an `X-Forwarded-For` header check when behind a reverse proxy.
Configurable via `magic_mountain.yml`: `rate_limit_trusted_proxies`.

**Rate limit key strategies**:
- **Primary**: By IP (simple, prevents password spraying)
- **Future**: By account name as secondary key — blocks rapid attempts on
  a single username even from different IPs (requires persistent storage)

### Testing

1. **Unit test** for `RateLimiter` class: verify count increments, window
   expiry, block/thaw cycle, and stale cleanup.
2. **Integration test** via `Test::Mojo`: fire N+1 login requests,
   verify 429 on the last one, wait for window, verify unblock.
3. **X-Forwarded-For test**: verify header-based IP resolution.

### Files to create/modify

| File | Action |
|------|--------|
| `lib/MagicMountain/RateLimiter.pm` | Create — rate limiter class |
| `lib/MagicMountain.pm` | Add `rate_limiter` helper, `rate_limit_check` bridge in `buildRoutes`, defaults in `defaultConfig` |
| `lib/MagicMountain/Controller/Sessions.pm` | Add failure/success recording to `create` |
| `magic_mountain.yml` | Add rate limit config |
| `t/rate_limiter.t` | Create — unit + integration tests |

---

## Infrastructure Backlog

| Concern | Priority | Notes |
|---------|----------|-------|
| HTTPS enforcement | Low | Handled at reverse proxy (nginx) or via Mojo config. |
| Password/email auth | Medium | Current name-only auth is fine for alpha. Email verification flow planned post-MVP. |
