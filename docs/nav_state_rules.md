# Nav State Rules

## Views

| View | Tab Label | Fragment | When Available |
|------|-----------|----------|----------------|
| `idle` | PROSPECT | `/idle?_format=fragment` | No active activity |
| `prospecting` | PROSPECT | `/prospecting?_format=fragment` | Activity phase = processing, type = prospecting |
| `market` | BAZAAR | `/market?_format=fragment` | Activity phase = negotiating, type = market_visit |
| `result` | HOME | `/result?_format=fragment` | Character has a pending `result` field |
| `home` | HOME | `/home?_format=fragment` | Always (character exists, no result pending) |
| `shed` | (secondary panel) | `/shed?_format=fragment` | Always (character exists) |
| `factions` | FACTIONS | `/factions?_format=fragment` | Always (secondary tab) |
| `skills` | CERTS | `/skills?_format=fragment` | Always |
| `pvp` | INTEL | `/pvp?_format=fragment` | Always |
| `account` | ACCOUNT | `/account?_format=fragment` | Always |
| `leaderboard` | (secondary panel) | `/leaderboard?_format=fragment` | Always |

## Tabs

Primary tabs: HOME, PROSPECT, BAZAAR, INTEL (PvP), CERTS.
Secondary tabs: FACTIONS, ACCOUNT, ?, MUTE.

### Progressive Tab Gating

New players start with only HOME and PROSPECT visible. Tabs are revealed
as the player hits natural gameplay milestones. The `onboarding` column
on Character is a persistent bitmask (default 0):

| Bit | Constant | Tab | Reveal when |
|-----|----------|-----|-------------|
| 0 | BIT_BAZAAR | BAZAAR | shed_count >= 1 (first artifact secured) |
| 1 | BIT_FACTIONS | FACTIONS | total sales >= 3 |
| 2 | BIT_SKILLS | CERTS | scrap >= `onboarding_skill_unlock_scrap` (default 100) |
| 3 | BIT_INTEL | INTEL | Skills revealed AND scrap >= 100 |

Once a bit is set, it is never cleared. The check runs on every `/game`
load in `SeasonManager::ensure_character`. Returning players with any
existing state (shed >= 1 OR sales >= 3 OR scrap >= 100) receive all
bits at once via fast-track.

Unrevealed tabs are omitted from the `/nav` response entirely. The JS
renders whatever it receives.

### Tab Active Status Per View

`✗` = inactive (greyed, `reason` shown as tooltip), `✓` = active (clickable),
`—` = tab not yet revealed (omitted from nav data, onboarding gate applies
regardless of view)

| Tab | home/idle | prospecting | market | result | factions | skills | account |
|-----|-----------|-------------|--------|--------|----------|--------|---------|
| HOME | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PROSPECT | ✓ ¹ | ✓ | ✗ ² | ✓ | ✓ | ✓ | ✓ |
| BAZAAR | —/✓ ³ | —/✗ ² | —/✓ | —/✓ | —/✓ ³ | —/✓ ³ | —/✓ ³ |
| INTEL | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ |
| CERTS | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ |
| FACTIONS | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ | —/✓ |
| ACCOUNT | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Footnotes:**
1. PROSPECT inactive if `$ap < 2` (reason: "Not enough AP (2 required)")
2. `reason`: "Complete your current activity first" / "Finish your current expedition first"
3. BAZAAR additionally inactive if `$ap < 1` (reason: "No AP remaining") or shed is empty (reason: "No artifacts in shed"). These resource checks apply regardless of view.

### Progress Overrides

- The home dashboard shows a **Begin with PROSPECT (costs 2 AP)** prompt
  when the player has no active activity, no shed items, and no scrap.
- When a tab is first revealed, a notice card appears in the primary
  content panel with flavor text and a Dismiss button. The notice is
  persisted via `pending_notices` bitmask and survives page refresh.
- Notices are dismissed via `POST /onboarding/dismiss-notice` which
  clears the bit and redirects to `/game`.

## Secondary View Mapping

| View | Secondary | Rationale |
|------|-----------|----------|
| home | factions | Browse factions from dashboard |
| idle | factions | See standings before choosing activity |
| prospecting | factions | See standings while deciding when to stop |
| result | factions | See standings after an outcome |
| market | shed | See inventory during negotiation |
| factions | leaderboard | See rankings alongside faction profiles |
| skills | leaderboard | See rankings while training |
| account | leaderboard | See rankings alongside settings |

## Context Bar Text Per View

| View | Context text |
|------|-------------|
| home/idle | Current Crier message (if any) |
| prospecting | `INSTABILITY X/Y  │  STAGE Z  │  VALUE W` (from artifact state) |
| market | `BUYER: faction_name  │  IRRITATION X  │  MOOD: state` (from customer state) |

## Nav Endpoint Response Shape

```json
{
  "current_view": "prospecting",
  "primary_fragment_url": "/prospecting?_format=fragment",
  "secondary_view": "factions",
  "secondary_fragment_url": "/factions?_format=fragment&panel=secondary",
  "tabs": [
    {"id": "prospect", "label": "PROSPECT", "active": true, "reason": null, "fragment_url": "/prospecting?_format=fragment"},
    ...
  ],
  "context": "INSTABILITY 7/14  |  STAGE STRAINED  |  VALUE 24"
}
```
