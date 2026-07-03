# How to Write Events

Events are YAML-defined, code-free content additions. Create or edit files in
`content/events/` — no Perl changes needed.

## Event Pools

| File | Trigger | Purpose |
|------|---------|---------|
| `content/events/prospecting.yml` | `begin` | Fires during Prospecting::begin (20% chance) |
| `content/events/market_visit.yml` | `begin` | Fires during MarketVisit::begin (15% chance) |
| `content/events/global.yml` | `day_start` | Fires once per day during maintenance (60% chance) |

## Event Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique identifier, `^[a-z][a-z0-9_]*$` |
| `weight` | yes | Relative probability (higher = more likely). Must be positive integer. |
| `trigger` | yes | `begin` or `day_start` |
| `text` | yes | Player-facing flavor text |
| `min_day` | no | Minimum season day for this event to fire |
| `max_day` | no | Maximum season day for this event to fire |
| `conditions` | no | Array of `{ predicate: value }` pairs (AND logic) |
| `effects` | yes* | Array of `{ effect_name: value }` (must have if no `choices`) |
| `choices` | yes* | Array of choice objects (must have if no `effects`) |

\* Exactly one of `effects` or `choices` is required.

## Choice Objects

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique within the event |
| `label` | yes | Button text shown to the player |
| `effects` | yes | Array of `{ effect_name: value }` applied when chosen |
| `conditions` | no | Array of `{ predicate: value }` — hides choice if conditions fail |

## Available Conditions (Prospecting Pool)

| Condition | Type | Description |
|-----------|------|-------------|
| `artifact_stage` | string | Current artifact stage: `stable`, `strained`, `unstable` |
| `scrap_gte` | integer | Character scrap >= N |
| `scrap_lte` | integer | Character scrap <= N |
| `score_lte` | integer | Character score <= N (catch-up) |
| `prospecting_gte` | integer | Prospecting skill >= N |
| `upcycling_gte` | integer | Upcycling skill >= N |
| `selling_gte` | integer | Selling skill >= N |

## Available Conditions (Market Visit Pool)

| Condition | Type | Description |
|-----------|------|-------------|
| `scrap_gte` | integer | Character scrap >= N |
| `selling_gte` | integer | Selling skill >= N |
| `standing_gte` | integer | Standing with current faction >= N |

## Available Effects (Prospecting Pool)

| Effect | Values | Description |
|--------|--------|-------------|
| `scrap_delta` | integer or `[min,max]` range | Change character scrap |
| `score_delta` | integer or `[min,max]` range | Change character score (only increase) |
| `value_delta` | integer or `[min,max]` range | Change artifact value |
| `instability_delta` | integer or `[min,max]` range | Change artifact instability |
| `behavior_add` | string (scalar only) | Add behavior tag to artifact |
| `ap_delta` | integer or `[min,max]` range | Change action points |

## Available Effects (Market Visit Pool)

| Effect | Values | Description |
|--------|--------|-------------|
| `multiplier_delta` | float (scalar only) | Add to offer multiplier (-0.50 to 0.50) |
| `irritation_floor` | integer (scalar only) | Set minimum customer irritation (0-10) |
| `irritation_delta` | integer or range | Change customer irritation |

## Available Effects (Global Pool)

| Effect | Values | Description |
|--------|--------|-------------|
| `instability_growth_delta` | integer (scalar only) | Extra instability per push (0-5) |
| `artifact_value_mult` | float (scalar only) | Artifact value multiplier (0.5-2.0) |
| `market_multiplier_delta` | float (scalar only) | Market offer delta (-0.50 to 0.50) |
| `prospect_ap_cost` | integer (scalar only) | AP cost per prospect action (1-4) |

## PB3K Text Style

- Write in ALL CAPS ALERT style for sensor readings
- Prefix with a category word: `STABILITY WARNING`, `SENSORY ALERT`, `GEOSCAN REPORT`
- Keep under 280 characters
- Use present tense, imperative where appropriate
- Use `{placeholder}` syntax for text tokens (future feature)

## Design Guidelines

1. **Weight relative to pool peers**: If the pool has 5 events with weight 5 each, your new event with weight 5 will have ~17% selection chance when an event fires.

2. **Day gates for pacing**: `min_day: 3` means the event only starts appearing on season day 3+. Use this to introduce complexity gradually.

3. **Catch-up via `score_lte`**: Events with `score_lte: 200` give struggling characters a boost. Good for rubberbanding.

4. **Choice events**: First choice (`bot-first-choice safety`) should be safe/reasonable — bots auto-pick the first eligible choice.

5. **Skill gates on choices**: Use `conditions` on individual choices (not events) to provide skill-based branching without blocking the whole event.

6. **Testing**: Set `MM_RAND_SEED` for deterministic event selection. Use `MM_EVENTS=1` in test mode to force events.
