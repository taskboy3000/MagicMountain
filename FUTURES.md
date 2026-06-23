# Futures — Magic Mountain

Unfinished business and planned work beyond the current MVP.

---

## MVP Categorization

See `AGENTS.md` for current implementation status.

| Category | Items |
|----------|-------|
| **Defer Past MVP** | MariaDB Migration, Commission System (§7.3), MarketVisit Enhancements, HTTPS / Password auth |

### Defer Past MVP

| Item | Effort | Why |
|------|--------|-----|
| MariaDB Migration | High | JSON works for single-server; arch doc says post-MVP (§18.2) |
| Commission System (§7.3) | Medium | Requires data model + MarketVisit changes; post-MVP feature |
| MarketVisit Enhancements (§6.5) | Low-Med | Basic one-shot flow works; multi-item/counter-offer is polish |
| HTTPS / Password auth | Low | Handled at reverse proxy; fine for alpha |

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

## Market Dynamics (§6.7) — DONE

Trait saturation (0.01/sale), daily faction appetite (2–4/day with 0.50×
penalty), and desperation bonus (2.0× after idle period). Implemented in
`Activity::MarketVisit.pm` (`_dynamic_multiplier`), tracked in
`season.faction_state`. The Desperate Recruiter underdog catch-up mechanic
is not yet implemented.

---

## Rate Limiting — DONE

IP-based + account-name-based rate limiter implemented:
- `lib/MagicMountain/RateLimiter.pm` — IP and name-based tracking,
  sliding window, block/thaw cycle, cleanup timer
- Rate-limit bridge in `MagicMountain.pm::buildRoutes` after maintenance gate
- `Retry-After` and `X-RateLimit-*` headers on all login responses
- Account-name keyed limiting (normalized lowercase) in `Sessions::create`
- Configurable via `magic_mountain.yml` or `defaultConfig`

---

## Infrastructure Backlog

| Concern | Priority | Notes |
|---------|----------|-------|
| HTTPS enforcement | Low | Handled at reverse proxy (nginx) or via Mojo config. |
| Password/email auth | Medium | Current name-only auth is fine for alpha. Email verification flow planned post-MVP. |
