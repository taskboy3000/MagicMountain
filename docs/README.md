---
tags:
  - index
  - meta
---

# Magic Mountain — Design Vault

This is the canonical design reference for **Magic Mountain**, a browser strategy
game where players extract artifacts from a mysterious Mountain and push their
luck to increase value while risking collapse.

## What This Is

The vault contains the design documents, architecture notes, and content
guidelines for the game. It is the single source of truth for how the game is
*intended* to work. Where the codebase and these docs disagree, the codebase
wins for implemented features; the docs win for aspirational and future-scope
features.

---

## Reading by Game Resource

Magic Mountain decomposes into tight, coherent game resources. Each resource
has its own design document or section. If you want to understand or modify a
specific part of the game, start with its resource page.

### Implemented Resources

These resources exist in the codebase today:

| Resource | Design Doc | Code Files |
|---|---|---|
| **Artifacts** — push/stop mechanics, collapse, breakthrough, signals | [Artifact Mechanics](Artifact%20Mechanics.md) | `lib/MagicMountain/Turn.pm`, `lib/MagicMountain/Artifact.pm` |
| **Artifact Content** — narrative text for individual artifacts | [Artifact Mechanics](Artifact%20Mechanics.md) §7 (Signal Design), [Core Design](Core%20Design.md) §19 (Content Strategy) | `content/artifacts/*.yml` |
| **Leaderboard** — player rankings | [Engine Design](Engine%20Design.md) §Leaderboards | `lib/MagicMountain/Leaderboard.pm` |
| **Tone & Writing** — narrative voice, vocabulary, style rules | [Tone Guide](Tone%20Guide.md) | `content/artifacts/*.yml` (text content) |

### Future-Scope Resources

These resources are designed but not yet implemented:

| Resource | Design Doc | Notes |
|---|---|---|
| **Factions** — environmental belief systems | [On Factions](On%20Factions.md) | World-building exists; mechanics are future scope |
| **Events** — interrupt, reflective, faction, contract | [Events](Events.md) | Designed; not yet wired to gameplay |
| **Environment / Seasons** — seasonal conditions | [Engine Design](Engine%20Design.md) §Environment, [Core Design](Core%20Design.md) §Seasonal Structure | Season framework exists; conditions are future scope |
| **Contracts** — multi-turn objectives | [Engine Design](Engine%20Design.md) §Contracts | Designed; not implemented |
| **PvP Combat** — end-of-day player conflict, hospital | [PvP Combat](PvP%20Combat.md) | Designed; not implemented |
| **Persistent Systems** — achievements, player history, Hall of Fame | [Engine Design](Engine%20Design.md) §Persistent Systems, [Engine Design](Engine%20Design.md) §Hall of Fame | Designed; not implemented |
| **Character Upgrades** — operational capability | [Engine Design](Engine%20Design.md) §Contracts / progression sections | Not explicitly scoped yet |

### Cross-Cutting Concerns

These documents span multiple resources:

| Concern | Documents |
|---|---|
| **Game Vision** — premise, player goal, philosophy, world | [Core Design](Core%20Design.md) |
| **Design Rationale** — why fixed turns, addictive traits, FQ lessons | [Design Lineage](Design%20Lineage.md) |
| **Core Loop** — time structure (turn/day/season), prospecting loop, constraints | [Engine Design](Engine%20Design.md) §Core Gameplay Loop, [Engine Design](Engine%20Design.md) §Global Design Constraints |
| **Implementation Plan** — what was built, in what order | [MVP 1.0](MVP%201.0.md) |
| **Architecture** — stack, layout, state, API, data flow | [Technical Architecture](Technical%20Architecture.md) |
| **Operations** — deployment, infrastructure, state persistence | [Implementation Context](Implementation%20Context.md) |

---

## Reading by Goal

If you don't know which resource to look up, start here:

| I want to...                                               | Start with                                                                                                        |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Understand the game's premise and emotional experience     | [The World of Magic Mountain](The%20World%20of%20Magic%20Mountain.md), then[Core Design](Core%20Design.md), then [Design Lineage](Design%20Lineage.md)                                       |
| Understand how the core loop works                         | [Engine Design](Engine%20Design.md) §Core Gameplay Loop                                                           |
| Understand artifact math (collapse, breakthrough, signals) | [Artifact Mechanics](Artifact%20Mechanics.md)                                                                     |
| Write new artifact content                                 | [Core Design](Core%20Design.md) §19 (Content Strategy), then [Tone Guide](Tone%20Guide.md), then `content/artifacts/*.yml` |
| Understand what was built vs. what is planned              | [MVP 1.0](MVP%201.0.md), then [Engine Design](Engine%20Design.md)                                                  |
| Deploy or maintain the game                                | [Technical Architecture](Technical%20Architecture.md), then [Implementation Context](Implementation%20Context.md) |
| Understand faction design                                  | [On Factions](On%20Factions.md), then [Core Design](Core%20Design.md) §Factions                                   |
| Understand the event system                                | [Events](Events.md), then [Engine Design](Engine%20Design.md) §Event System                                      |
| Understand PvP combat design                               | [PvP Combat](PvP%20Combat.md), then [Core Design](Core%20Design.md) §14 (PvP principles)                           |
| Understand season structure and Hall of Fame               | [Core Design](Core%20Design.md) §6 (Seasonal Structure), then [Engine Design](Engine%20Design.md) §Hall of Fame   |

---

## Document Index

| Document | Role | Scope |
|---|---|---|
| [The World of Magic Mountain](The%20World%20of%20Magic%20Mountain.md) | The setting of the Game, tone, world structure, philosophy | Vision |
| [Core Design](Core%20Design.md) | Game premise, player goal, tone, world structure, philosophy | Vision |
| [Design Lineage](Design%20Lineage.md) | Why fixed turns, addictive traits, FQ lessons | Rationale |
| [Engine Design](Engine%20Design.md) | Time structure, core loop, artifact/event/world systems | Systems |
| [Artifact Mechanics](Artifact%20Mechanics.md) | Push/stop math, collapse formula, breakthrough, signals, API shapes | Mechanics |
| [MVP 1.0](MVP%201.0.md) | What was built; the canonical implementation plan | Plan (complete) |
| [Tone Guide](Tone%20Guide.md) | Narrative voice, writing style, vocabulary, tone rules | Content |
| [On Factions](On%20Factions.md) | Faction system design and world influence | Future scope |
| [Technical Architecture](Technical%20Architecture.md) | Stack, layout, state, API, data flow | Architecture |
| [Implementation Context](Implementation%20Context.md) | Deployment, infrastructure, state persistence | Operations |
| [Events](Events.md) | Event types, YAML structure, engine responsibilities | Future scope |
| [PvP Combat](PvP%20Combat.md) | End-of-day player conflict, hospital, balance rules | Future scope |

---

## Source of Truth

| Layer | Source of Truth |
|---|---|
| **Implemented mechanics** | `lib/MagicMountain/Turn.pm`, `lib/MagicMountain/Artifact.pm` |
| **Artifact content** | `content/artifacts/*.yml` |
| **API contract** | `lib/MagicMountain/Controller/Api.pm` |
| **State persistence** | `lib/MagicMountain/State.pm` |
| **Game rules (intended)** | This vault |

---

*Last updated: 2026-05-24*
