# Futures — Magic Mountain

Unfinished business and planned work beyond the current MVP.

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
