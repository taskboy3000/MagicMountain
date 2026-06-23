---
tags:
  - events
  - future-scope
---
# Magic Mountain — Events (v1.0)

*Last updated: 2026-05-24*

This document describes the event system as a game resource.

Events provide narrative texture, world context, and occasional mechanical effects. They are the primary way the world reacts to the player and itself.

---

## Event Types

### Turn-Based Events (Consume Turns)

#### Interrupt Events

Interrupt events replace a prospecting turn.

They may include:
- narrative situations
- faction interactions
- contracts or opportunities
- small bonuses or setbacks

These events:
- add variety
- break repetition
- expose the world and factions

Interrupts must:
- support the core loop
- not dominate gameplay

### Free Events (Do NOT Consume Turns)

Free events provide narrative context only.

#### Types

- Reflective events (world reacting to itself)
- Flavor events (atmosphere)

#### Rules

- no player input
- no mechanical effect
- short and skippable
- never replace a turn

---

## Event Mix

- Most events (about 70–80 percent) are prospecting events
- The rest are interrupt events

## Design Rule

Prospecting is the core loop.
Interrupt events support pacing and narrative, not replace the loop.

---

## Event Categories

| Category | Description |
|---|---|
| Opportunity | Offer a choice with potential benefit |
| Friction | Introduce complication or cost |
| Choice | Require a decision with unclear outcome |
| Faction | Reflect or shift faction standing |
| Contract | Advance or complicate an active contract |
| Disruption | Temporarily alter available actions or context |

---

## YAML Structure

### Example — Interrupt Event

```yaml
id: purifier_inspection_001
type: interrupt
tags:
  - faction
  - purifier
  - inspection

conditions:
  faction_influence:
    purifier: high

text: >
  Two inspectors stop beside your workbench.
  They do not ask what the device does.
  They ask why you still have it.

choices:
  - id: comply
    label: Let them inspect it
    outcome: small_reputation_shift

  - id: argue
    label: Explain that it is harmless
    outcome: risk_minor_setback
```

### Fields

| Field | Required | Description |
|---|---|---|
| `id` | yes | Unique identifier |
| `type` | yes | `interrupt` or `reflective` |
| `tags` | no | List of category tags |
| `conditions` | no | Eligibility conditions (e.g., faction standing, season phase) |
| `text` | yes | Player-facing narrative text |
| `choices` | no | List of choices, each with `id`, `label`, `outcome` |

---

## Engine Responsibilities

The event engine:
- loads event files from `content/events/`
- validates required fields and types
- filters eligible events based on current game state
- selects one event using weighted randomness
- applies the event's mechanical effects (if any)
- renders text and presents choices to the player
- resolves outcomes based on player selection or random roll

## Author Responsibilities

The content author defines:
- event id and type
- eligibility conditions
- narrative text
- available choices and their labels
- outcome references (the engine defines what each outcome ID means)

---

## Future Scope

The event system is not yet implemented. When it is:
- `content/events/` will contain YAML files for each event category
- `MagicMountain::Content` will load and validate them
- `MagicMountain::Turn` will trigger eligible events during prospecting
- Event outcomes will be resolved through `MagicMountain::State` mutations
