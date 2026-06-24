# Nav State Rules

## Views

| View | Tab Label | Fragment | When Available |
|------|-----------|----------|----------------|
| `idle` | PROSPECT | `/idle?_format=fragment` | No active activity |
| `prospect` | PROSPECT | `/prospecting?_format=fragment` | Activity phase = processing, type = prospecting |
| `market` | BAZAAR | `/market?_format=fragment` | Activity phase = negotiating, type = market_visit |
| `shed` | SHED | `/shed?_format=fragment` | Always (character exists) |
| `factions` | FACTIONS | `/factions?_format=fragment` | Always |
| `skills` | SKILLS | `/skills?_format=fragment` | Always |
| `bulletin` | BULLETIN | `/crier?_format=fragment` | Always |

## Tab Active Status Per View

`✗` = inactive (greyed, `reason` shown as tooltip), `✓` = active (clickable)

| Tab | idle | prospect | market | shed | factions | skills | bulletin |
|-----|------|----------|--------|------|----------|--------|----------|
| PROSPECT | ✓ | ✓ | ✗ ¹ | ✓ | ✓ | ✓ | ✓ |
| SHED | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| BAZAAR | ✓ ² | ✗ ¹ | ✓ | ✓ ² | ✓ ² | ✓ ² | ✓ ² |
| FACTIONS | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| SKILLS | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| BULLETIN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Footnotes:**
1. `reason`: "Complete your current activity first"
2. BAZAAR additionally inactive if `$ap < 1` (reason: "No AP remaining") or shed is empty (reason: "No artifacts in shed"). These resource checks apply regardless of view.

## Secondary View Mapping

| View | Secondary | Rationale |
|------|-----------|----------|
| idle | shed | See what you have before choosing an activity |
| prospect | shed | See inventory while deciding when to stop |
| market | factions | See standing/influence during negotiation |
| shed | factions | Browse factions while reviewing inventory |
| factions | leaderboard | See rankings alongside faction profiles |
| skills | leaderboard | See rankings while training |
| bulletin | leaderboard | See rankings alongside news |

## Context Bar Text Per View

| View | Context text |
|------|-------------|
| idle | `PROSPECT — 2 AP  │  SHED — N ITEMS  │  BAZAAR — 1 AP` (adjusted for AP/items) |
| prospect | `INSTABILITY X/Y  │  STAGE Z  │  VALUE W` (from artifact state) |
| market | `BUYER: faction_name  │  IRRITATION X  │  MOOD: state` (from customer state) |

## Nav Endpoint Response Shape

```json
{
  "current_view": "prospect",
  "primary_fragment_url": "/prospecting?_format=fragment",
  "secondary_view": "shed",
  "secondary_fragment_url": "/shed?_format=fragment",
  "tabs": [
    {"id": "prospect", "label": "PROSPECT",  "active": true,  "reason": null, "fragment_url": "/prospecting?_format=fragment"},
    ...
  ],
  "context": "INSTABILITY 7/14  |  STAGE STRAINED  |  [PUSH]  [STOP]"
}
```
