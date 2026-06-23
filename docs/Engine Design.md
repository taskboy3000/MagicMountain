---
tags:
  - push-model
  - loop
---

*Last updated: 2026-05-24*

# Magic Mountain - Engine Operations v0.3

## Purpose

This document describes how the game operates at a high level.

It defines:
- how the game runs each turn, day, and season
- how systems interact
- what constraints must always hold

It does not define:
- exact math
- stat formulas
- artifact tables

For server-side module boundaries and the per-request lifecycle, see [Technical Architecture](Technical%20Architecture.md).

---

# Core Time Structure

## Time Units

The game operates on three time scales:

1. Turn
2. Day
3. Season

---

## Turn

A turn is one player-facing event.

Most turns are **prospecting events**.
Some turns are **interrupt events** *(future scope)*.

---

# Core Gameplay Loop

## Core Idea

Each turn is an event where the player pulls an artifact from the Mountain
and tries to turn it into value.

## Turn Structure

- Player gets 10 events per day
- Each event is either:
  - Prospecting (default)
  - Interrupt (rare) — *future scope*

## Prospecting Turn (Primary Loop)

The player pulls an artifact from the Mountain and attempts to convert it into value.

### Flow

1. Artifact is extracted
2. Player begins processing it
3. Player may push repeatedly
4. Player chooses when to stop
5. Outcome resolves

### Push Your Luck

- Each push:
  - increases value
  - increases risk
- Player can stop anytime to secure value

### Failure

If pushed too far:
- artifact collapses
- main reward lost
- all value is lost (zero salvage)

### Success

- Stopping early:
  - lower but safe reward
- Pushing further:
  - higher reward, higher risk

### Artifact Behavior

Each artifact has hidden traits:
- value potential
- `max_instability` (instability cap)
- `instability_growth` range per push

Collapse is probabilistic based on the ratio of current instability to `max_instability` (see [Artifact Mechanics](Artifact%20Mechanics.md) §5).

*Future scope: resistance, signal clarity*

### Signals

Artifacts show instability through description:
- stable → clean behavior
- strained → uneven behavior
- unstable → clear warning signs

No numbers are shown.

### Player Skill

Skill = judging when to stop

Players learn:
- how artifacts behave
- how far to push
- when to take profit

### Progression

Improves:
- ability to read signals
- ability to handle instability

Does NOT remove risk.

### Design Rules

- no fixed safe number of pushes
- no visible probabilities
- risk is always present
- higher rewards require risk

### Summary

Repeat: pull artifact → push for value → decide when to stop

Win by managing risk better than other players.

### Design Rationale

See [Design Lineage](Design%20Lineage.md) for why 10 turns/day and fixed turns were chosen, and how the core loop was validated against Funeral Quest and the five addictive traits of browser strategy games.

---

## Behavior Evolution Under Pressure

Pushing an artifact applies pressure to make it behave more strongly or more predictably.

### Core Effects

#### Instability
- behavior becomes less controlled

#### Breakthrough (MVP)
- auto-stop with multiplier when a hidden threshold is crossed
- at most one breakthrough per artifact

*Future scope: Reinforcement, Revelation*

---



# Artifact System

## Artifact Generation (High-Level)

Artifacts are incomplete systems with observable behavior but no explicit identity.

### Structure

Artifacts are built from:
- hidden archetypes
- observable behaviors
- partial functionality

### Archetypes (Hidden)

Examples include:

- energy systems
- communication systems
- sensor systems
- medical systems
- food systems
- propulsion systems
- weapon systems
- field systems
- transformation systems
- storage systems

### Behavior

Artifacts may exhibit:
- heat
- motion
- signal
- reaction
- storage
- transformation
- field effects

Artifacts typically combine multiple behaviors.

---

## Initial State

Artifacts begin:
- partially functional
- unstable
- incomplete

Some behaviors are visible immediately.
Others emerge through pushing.

---

## Variation

Artifacts vary in:
- complexity
- stability
- clarity

---

# Event System

## Turn-Based Events (Consume Turns)

### Interrupt Events *(future scope)*

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

## Event Mix

- Most events (about 70–80 percent) are prospecting events
- The rest are interrupt events

## Design Rule

Prospecting is the core loop.
Interrupt events support pacing and narrative, not replace the loop.

---

## Event Categories

- Opportunity Events
- Friction Events
- Choice Events
- Faction Events
- Contract Events
- Disruption Events

---

## Free Events (Do NOT Consume Turns)

Free events provide narrative context only.

### Types

- Reflective events (world reacting to itself)
- Flavor events (atmosphere)

### Rules

- no player input
- no mechanical effect
- short and skippable
- never replace a turn

---

# Content Loading

The engine loads authored content from structured files rather than hardcoding it.

## Process

1. **Load** — read YAML files from `content/`
2. **Validate** — check required fields and data types
3. **Select** — filter eligible content based on game state and conditions
4. **Apply** — run game rules against the selected content
5. **Render** — produce player-facing text and choices

## Content Domains

| Domain | Location | Described In |
|---|---|---|
| Artifacts | `content/artifacts/*.yml` | [Artifact Mechanics](Artifact%20Mechanics.md) §YAML Structure |
| Events | `content/events/*.yml` | [Events](Events.md) §YAML Structure |
| World text | `content/world/*.yml` | *(future scope)* |

## Validation

The engine validates:
- required fields are present
- field types match expectations (numbers, strings, lists)
- references resolve (e.g., `outcome` IDs exist)
- conditions are syntactically valid

Invalid files should fail fast at load time, not at runtime.

---

# World Systems

## Faction Influence

Factions are environmental forces.

Players do not join factions.

### Core Principle

Factions influence:
- what is valuable
- what is acceptable
- what events occur

They do NOT influence:
- core mechanics
- success chances

---

## Effects

Factions influence:
- event distribution
- NPC reactions
- contract availability
- narrative tone

---

## Environment *(future scope)*

Each season has a defining condition.

Examples:
- drought
- cold
- overgrowth
- instability

Environment affects:
- tone
- event weighting
- artifact usefulness

---

# Player Systems

## Contracts

Contracts:
- span multiple turns or days
- provide larger rewards
- create continuity

They must not replace prospecting.

---

## PvP

PvP is optional and occurs at end of day.

### Structure

1. Break-In
2. Action

### Actions

- Pilfer (low risk)
- Confront (higher risk)

### Outcomes

- win → moderate gain
- lose → small loss + hospital

---

## Hospital

Hospital is a **PvP consequence**, not a generic system.

See [PvP Combat](PvP%20Combat.md) §Hospital for the canonical mechanic:
- losing PvP removes remaining daily actions
- cannot attack while hospitalized
- duration lasts until the attacker logs back in with new turns

---

## Leaderboards

Players are ranked by **`score` descending**.

- **`scrap`** — current liquid wealth (can be spent or lost to PvP)
- **`score`** — cumulative season score, increased every time a player stops an artifact and converts its value

The leaderboard currently uses a single numeric metric (`score`) for simplicity. The four dimensions listed in [Core Design](Core%20Design.md) §2 (wealth, reputation, influence, operational efficiency) are **aspirational** and may inform future scoring systems.

Must not be dominated by:
- randomness
- PvP

---

# Daily Flow

## Day

Each player receives 10 turns.

A day includes:
- turn usage
- faction shifts
- leaderboard updates
- contract progression

---

## Daily Maintenance

At rollover:

1. restore turns
2. update contracts
3. update factions
4. adjust event weights
5. refresh world text
6. refresh leaderboards

---

# Seasonal Structure

## Season

~30 days.

Players:
- compete for rank
- influence factions
- adapt to environment

---

## Season Start

- choose location
- choose environment
- reset progress
- initialize factions
- open leaderboard

---

## Season End

- lock rankings
- generate recaps
- determine faction outcomes
- archive results
- reset world

---

## Hall of Fame

The Hall of Fame records the **winner of each past season**.

### Contents

For each completed season:
- season ID and dates
- winning player name
- winning score
- final leaderboard (top N players)
- notable world outcomes (faction dominance, environment, etc.)

### Rules

- Hall of Fame entries are **read-only** after a season ends
- Past results do not affect current season balance (no carryover bonuses)
- Players can browse past seasons but cannot interact with them
- The Hall of Fame exists to give long-term meaning to competition

### Display

- accessible from the main UI
- shows a list of past seasons
- tapping a season shows full results

---

## Reset Philosophy

The Mountain disappears and returns elsewhere.

Reset should feel like:
- closure
- consequence
- renewal

---

# Recaps

## Player Recap

Includes:
- rank
- score
- key decisions
- notable outcomes

---

## World Recap

Describes:
- faction dominance
- societal shifts
- consequences

No moral judgment is given.

---

# Persistent Systems

May include:
- player history
- achievements
- past rankings
- Hall of Fame (season winners)

Must not affect fairness.

These systems provide memory and context. They do not confer mechanical advantage in the current season.

---

## Design Rationale

See [Design Lineage](Design%20Lineage.md) for the historical analysis of action-economy models, the five addictive traits, and Funeral Quest lessons that informed these engine decisions.

# Global Design Constraints

### Core Loop
- Prospecting is the dominant activity
- Push-your-luck is the core mechanic
- Each turn is an event, not a menu of actions
- The core loop must remain fast and repeatable
- See [Design Lineage](Design%20Lineage.md) for why fixed turns (10/day) and the "log in, use turns, come back tomorrow" rhythm were chosen

### Session Rhythm
> The core loop must support: log in, use turns, make progress, come back tomorrow.

### Risk and Uncertainty
- There is no fixed safe number of pushes
- Risk must be felt through signals, not numbers
- Failure must always be possible
- Players must feel responsible for failure

### Player Experience
- Players always have a way to make some progress each day
- Stopping early must always be a valid strategic choice
- Higher rewards require higher risk
- The loop must never become solved or purely mechanical

### Interruptions and Variety
- Prospecting is the primary source of progress
- Interrupt events support pacing, variety, and world context
- Interrupt events must not dominate or replace the core loop

### Random Event Boundaries
- No random event should cause catastrophic loss of player progress
- No random event should grant overwhelming advantage
- Random events must not remove risk from artifact processing
- Random events must not make PvP or high-risk play trivially safe

### Narrative and Tone
- The game never judges player choices
- Characters act rationally within their own beliefs
- The world is grounded, not self-aware or absurd on its surface

### Competition and Motivation
- The primary motivation is to win the season (leaderboard)
- Strategy emerges from risk-taking under competition
- There is no single optimal playstyle

### System Philosophy
- Systems should produce narrative, not replace it
- Player skill is judgment, not memorization or math
