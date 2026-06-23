---
tags:
  - world
  - future
  - factions
---

## Purpose

This document summarizes the design decisions for how factions function in the game.

Factions are not player-aligned systems. They are environmental forces that:

- shape the world
- influence what is valuable
- transform available opportunities
- create narrative continuity

They must enhance the core loop without replacing it.

---

# Core Principles

## Players Do Not Join Factions

- players are independent opportunists
- no faction membership
- no faction skill trees
- no permanent alignment

---

## Factions Are Environmental Forces

Factions represent:

- cultural pressure
- economic demand
- ideological influence

They operate at the world level, not the player level.

---

## Factions Do Not Modify Core Mechanics

Factions must NOT change:

- push mechanics
- instability calculations
- collapse probability
- player stats

Core loop integrity must be preserved.

---

## Factions Modify Meaning, Not Behavior

Key principle:

> Factions do not change what artifacts do.  
> They change what artifacts *mean*.

This affects:

- perceived value
- desirability
- social risk
- narrative framing

---

# Primary Effects of Factions

## 1. Economic Influence

Factions influence:

- what artifacts are desirable
- what artifacts are taboo
- how easily artifacts can be sold

Example:

- Purifiers dominant:
  - weapons harder to sell
  - unstable tech viewed negatively

- Syndicate dominant:
  - weapons highly valued
  - risky tech rewarded

---

## 2. Event Transformation (Core Mechanic)

Factions do not just weight events.

They can:

- suppress events
- replace events
- convert events into reflection (non-interactive)

---

## Event Transformation Types

### A. Suppression → Reflection

Original event is removed and replaced with a narrative-only event.

Example:

Original:
- "A weapons merchant arrives. Buy / ignore."

Transformed:
- "You notice fewer weapons in circulation. The traders who once carried them are gone."

Effects:

- no player choice
- no mechanical impact
- reinforces world state

---

### B. Suppression → Alternate Event

Original event is replaced with a different opportunity.

Example:

Original:
- weapons merchant

Replacement:
- purifier confiscation event
- dismantling service offer

Effects:

- maintains gameplay flow
- changes opportunity shape

---

### C. Partial Suppression

Original event still occurs, but less frequently.

This preserves unpredictability.

---

## 3. Atmospheric Reflection

Factions generate:

- ambient text
- reflective events
- world reactions

These:

- do not consume turns
- do not affect resources
- reinforce continuity

---

# Design Constraints

## Preserve Player Agency

- most turns must still offer meaningful choices
- reflective events must not dominate

---

## Reflection Events Are Free

- do not consume turns
- do not block player progress

---

## Maintain Legibility Over Time

Players should gradually learn:

- which factions influence which outcomes
- how the world is shifting

Without explicit explanation.

---

## Avoid Deterministic Rules

Do NOT implement:

IF faction == purifier THEN always replace weapons events

Instead use:

- probabilistic transformation
- partial suppression
- varied outcomes

---

## Do Not Let Factions Dominate Gameplay

Factions should:

- influence decisions
- not dictate optimal strategy
- not become the primary system

---

# Event Tagging Model

Events are categorized using tags.

Example:

```yaml
event_id: weapons_merchant
tags:
  - weapons
  - trade

### YAML example

purifiers:
  suppress_tags:
    - weapons

  transformations:
    weapons:
      reflective:
        - "You notice fewer weapons in circulation."
        - "The traders who once carried arms are gone."

      replacement:
        - purifier_confiscation_event
        - purification_service_event

      allow_original_chance: 0.2
      
      
### psuedo code
function resolve_event(base_event, world_state):

    faction = world_state.dominant_faction

    if base_event.tags intersect faction.suppress_tags:

        roll = random()

        if roll < reflective_chance:
            return generate_reflective_event(faction, base_event)

        else if roll < replacement_chance:
            return select_replacement_event(faction, base_event)

        else:
            return base_event   # rare, original slips through

    else:
        return base_event
        
### reflective event
function generate_reflective_event(faction, base_event):

    text = random_choice(faction.transformations[base_event.tag].reflective)

    return {
        type: "reflective",
        consumes_turn: false,
        text: text
    }

### replacement event
function select_replacement_event(faction, base_event):

    replacement_list = faction.transformations[base_event.tag].replacement

    new_event_id = random_choice(replacement_list)

    return load_event(new_event_id)
    