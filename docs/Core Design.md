---
tags:
  - setting
  - vision
---
Magic Mountain – Core Design Document (v0.1)

1. Core Premise

A mysterious phenomenon known as the Mountain appears in the world for a limited time.

It attracts:

- opportunists
- scholars
- cultists
- traders
- scavengers

Players are among them.

They compete to extract the most value before:

The Mountain disappears at the end of the season.

  

2. Player Goal

Win the season.

A season is a **~30 day tournament**. Players compete for the **highest rank on the leaderboard**.

Standing is determined by:

- wealth
- reputation
- influence
- operational efficiency

The game must always clearly communicate:

“Am I winning?”

  

3. Core Experience

Each session (3–10 minutes):

- Player receives limited actions
- Encounters strange events
- Makes meaningful choices
- Gains resources or consequences

Each session should produce:

- one memorable moment
- one meaningful decision
- one incremental gain

  

4. Core Loop

Actions → Events → Outcomes → Progression → Advantage

Player actions include:

- Prospect artifact (extract and push an artifact from the Mountain; current UI verb is "start artifact" — see [Design Lineage](Design%20Lineage.md) §Note on Terminology)
- Take Contracts
- Work their Operation

Each action generates:

- a narrative event
- a decision
- an outcome

  

5. The Mountain

The Mountain is:

- real (not supernatural in origin)
- not understood
- not fully explained
- a source of:

- artifacts
- danger
- mystery
- opportunity

Design Rule

The Mountain is defined by competing interpretations, not a single truth.

  

6. Seasonal Structure

Each season:

- The Mountain appears in a new location
- The environment changes (drought, swarm, fertility, etc.)
- Players compete for ~30 days for the highest leaderboard rank
- The Mountain disappears
- Results are finalized
- A new season begins

Design Rule

The reset is part of the fiction.

  

7. Two-Layer System

Layer 1 — Player Game

- score
- resources
- upgrades
- competition

Layer 2 — World Simulation

- faction influence
- environmental tone
- event distribution
- societal outcomes

Design Rule

Players pursue victory.  
The system produces consequences.

  

8. Factions

Factions represent belief systems and priorities, not classes.

Each faction:

- identifies a real human concern
- is partially correct
- creates unintended consequences

Example Themes:

- Meaning (religious)
- Knowledge (scholars)
- Prosperity (traders)
- Safety (purifiers)
- Discovery (seekers)

  

9. Faction Mechanics

- Players may align with factions (optional, not permanent)
- Factions provide small, situational advantages
- No faction is dominant or optimal

Design Rule

Factions are strategic lenses, not power classes.

  

10. Faction Influence

Player actions subtly affect faction influence.

Faction dominance affects:

- event frequency
- NPC behavior
- opportunities
- narrative tone

Design Rule

Factions shape the world, not the rules.

  

11. Environmental Effects (Per Season)

Each season introduces a condition:

Examples:

- drought
- overgrowth
- insect swarms
- unstable phenomena

Effects include:

- slight mechanical pressure
- strong event weighting
- narrative tone shifts

Design Rule

Environment creates pressure.  
Factions determine response.

  

12. Narrative Philosophy

- events are authored
- worldbuilding is implied
- ambiguity is preserved

Design Rule

The game suggests. The player imagines.

  

13. Tone

- absurd but grounded
- dark but not cynical
- humorous through plausibility

Design Rule

People behave rationally in an irrational world.

  

14. PvP

- optional, limited
- redistributes value
- creates rivalry

Design Rule

PvP creates tension, not victory.

  

15. Progression

Players build:

- resources
- reputation
- operational capability

Progression loop:

Small gains → better options → better gains

  

16. End-of-Season Results

Players receive:

Personal Results

- rank
- score
- achievements

World Results

- faction dominance
- societal outcomes
- narrative summary

Design Rule

The game reports outcomes. It does not judge them.

  

17. No Optimal Outcome

There is no “best” world state.

Each dominant approach creates:

- benefits
- tradeoffs
- consequences

Design Rule

Every solution creates new problems.

  

18. Core Design Philosophy

Players act to win.  
Their actions unintentionally shape a temporary society.  
The Mountain reveals what people become under pressure.



19. Content Strategy

Narrative content lives outside application code.

The game engine loads structured content files and executes them through shared rules.

### Format

Use YAML for authored content.

YAML is preferred because it is:
- readable
- easy to edit by hand
- structured enough for validation
- friendly to version control

### Separation Principle

YAML defines content.

Code defines rules.

Do not put complex game logic inside YAML.

### Design Goal

Adding content should not require editing game engine code.

A new event or artifact text should be added by writing or editing a YAML file.

### Engine Responsibility

The engine should:
- load content files
- validate required fields
- select eligible content
- apply game rules
- render text and choices

### Author Responsibility

The content file should define:
- title or internal id
- event type
- eligibility conditions
- player-facing text
- choices, if any
- outcome references
- tags



