# Futures — Magic Mountain

Unfinished business and planned work beyond the current MVP.

---

## MVP Categorization

Based on `GAME_ARCHITECTURE.md` and current codebase state (core activities
not yet implemented). See `AGENTS.md` for implementation status.

| Category | Items |
|----------|-------|
| **Must-Have for MVP** | None. The real MVP blocker is building Prospecting, MarketVisit, Shed, and Maintenance. Everything in this doc is secondary. |
| **Nice-to-Have Before Real Users** | CSRF protection, Season Finalization UI, Crier Narrative Expansion |
| **Defer Past MVP** | MariaDB Migration, Market Dynamics (§6.7), Commission System (§7.3), Bot Policy Framework, MarketVisit Enhancements, Rate limiting / HTTPS / Password auth |

### Nice-to-Have Before Real Users

| Item | Effort | Why |
|------|--------|-----|
| CSRF protection | Low | Needed before accepting writes from real browsers |
| Season Finalization UI | Low | CLI exists; a web button is cheap and closes the loop |
| Crier Narrative Expansion | Low | Content-only, built on existing faction_state diffing |

### Defer Past MVP

| Item | Effort | Why |
|------|--------|-----|
| MariaDB Migration | High | JSON works for single-server; arch doc says post-MVP (§18.2) |
| Market Dynamics (§6.7) | High | Explicitly "not required for initial implementation" |
| Commission System (§7.3) | Medium | Requires data model + MarketVisit changes; post-MVP feature |
| Bot Policy Framework (§14.1–14.2) | Medium | Current hardcoded strategy is sufficient for testing |
| MarketVisit Enhancements (§6.5) | Low-Med | Basic one-shot flow works; multi-item/counter-offer is polish |
| Rate limiting / HTTPS / Password auth | Low | Fine for alpha; deferred per AGENTS.md |

---

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

## Season Finalization (§8.3)

An admin command exists (`end-season`) and ArtifactDisposition records
are created on each sale. SeasonRecords are created during finalization.
The remaining gap is a web UI for the admin to trigger the command.

---

## Commission System (§7.3)

After a player's second sale to a faction, that faction may issue a
commission — a standing offer for specific artifact traits at a premium.
The data model (standing, faction_sales) is in place. The trigger logic,
commission storage, premium application in MarketVisit, and expiry through
prospecting attempts are not yet implemented.

---

## Bot Policy Framework (§14.1–14.2)

Bots currently use a single hardcoded strategy (push until unstable, sell
first match). The GAME_ARCHITECTURE.md defines pluggable push policies
(fixed_pushes, instability_cap, stage_guard, greed, value_target) and
sell policies (highest_offer, faction_loyalist, opportunist, desperate,
hoarder). YAML bot profiles can then drive population simulations with
mixed strategies.

---

## MarketVisit Enhancements (§6.5)

Counter-offers and multi-item visits are not yet implemented. The current
implementation is one-shot: match → sale, mismatch → settle or irritation
→ try another item or storm off.

---

## Crier Narrative Expansion

The crier generates daily messages from faction_state diffs and
season day progression (implemented). Future work includes:
- `content/text/commission_triggers.yml` and
  `content/text/negotiation_reactions.yml` for richer faction text
- Per-faction disposition flavor in market visits

---

## Market Dynamics (§6.7)

Supply/demand, faction appetite caps, trait saturation, and the
Desperate Recruiter rubber-banding mechanic. All planned but deferred
past MVP.

---

## Infrastructure Backlog

| Concern | Priority | Notes |
|---------|----------|-------|
| CSRF protection | Medium | Mojolicious `csrf_protect` plugin. Needed before accepting writes from real users. |
| Rate limiting | Medium | Brute-force prevention on login. Mojo `under` hooks can count attempts. |
| HTTPS enforcement | Low | Handled at reverse proxy (nginx) or via Mojo config. |
| Password/email auth | Medium | Current name-only auth is fine for alpha. Email verification flow planned post-MVP. |
