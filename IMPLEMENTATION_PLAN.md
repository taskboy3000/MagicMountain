# Town Crier — Narrative System

## Data Source

The crier detects faction-state changes by diffing `faction_state` snapshots
day over day. During maintenance, before applying the new day's decay/AP
refresh, snapshot the current `faction_state`. After all maintenance work is
done, compare old vs new to generate messages.

Storage: `season.crier_snapshot` column (hashref, a copy of faction_state
from the previous day). Set during maintenance after generating messages.

## Content

**File**: `content/text/crier.yml`

```yaml
crier_messages:
  faction_surge:
    - "The {faction} is on a tear — {influence_gain} value in artifacts acquired overnight."
    - "Word from the Bazaar: {faction} buyers can't get enough. Up {count} deals today."
  faction_slump:
    - "The {faction} caravan was light today. Only {count} artifacts changed hands."
    - "A {faction} quartermaster was seen leaving empty-handed. Slow day."
  faction_dominance:
    - "The {faction} now leads all factions with {influence} total value. Their flag flies higher."
  milestone:
    - "The {faction} just received their {count}th artifact of the season. The Crier notes the occasion."
  season_opening:
    - "A new season dawns. The mountain stirs. Five factions circle."
  generic:
    - "The mountain looms as always. Another day, another chance."
    - "Trade routes are open. The Bazaar hums."
```

## Message Selection Logic

Ran during `on_maintenance` callback:

1. Load `season.faction_state` → `season.crier_snapshot`
2. If no snapshot exists (day 1): pick a `season_opening` or `generic` message
3. For each faction, diff:
   - `influence_gain = current.influence - snapshot.influence`
   - If influence_gain > threshold: `faction_surge` message
   - If influence_gain == 0 and `artifacts_received > 0`: `faction_slump` message
   - If faction is the new leader: `faction_dominance` message
   - If `artifacts_received` crossed a round number (10, 25, 50): `milestone`
4. Pick at most ONE message per day (highest priority wins)
5. Store as `season.crier_message` (plain text)
6. Update snapshot: `season.crier_snapshot = current faction_state`

## Integration

**Maintenance callback**: Add crier logic after decay/AP refresh, before the
season-length warning.

**Game state** (`/game` JSON): Include `world_message` field:

```json
{
  "ok": 1,
  "player": { ... },
  "season": { "day": 5, "total_days": 30 },
  "world_message": "The Syndicate is on a tear — 42 value in artifacts acquired overnight."
}
```

**UI**: The `world_message` is already slotted in the spec (§13.3). The game
JS SPA would display it in a banner or flavor-text area. Currently absent
from both the JSON response and the template — needs wiring.

## Execution Order

```
Phase 1 — Add crier_snapshot and crier_message columns to Season model
Phase 2 — Create content/text/crier.yml
Phase 3 — Implement Crier message selection logic (standalone module or
          inline in maintenance, no app coupling)
Phase 4 — Wire into on_maintenance callback
Phase 5 — Add world_message to /game JSON response
Phase 6 — Display world_message in game UI template
Phase 7 — Tests
```
