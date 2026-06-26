---
tags:
  - pvp
  - future-scope
---

*Last updated: 2026-05-24*

*Status: Partially designed. Core principles and structure are set; formulas and stats need refinement.*

This document describes player-versus-player conflict as a game resource.

PvP is **optional, limited, and designed to create tension rather than determine victory.** It redistributes value between players and generates rivalry, but it is not the primary path to winning the season.

---

## Design Principles

### From Core Design

> PvP creates tension, not victory.

- **Optional** — players can engage or ignore it
- **Limited** — restricted in frequency and scope
- **Redistributes value** — moves scrap between players; does not create it from nothing
- **Creates rivalry** — gives the leaderboard emotional stakes beyond raw numbers

### From Global Constraints

- Random events must not make PvP or high-risk play trivially safe
- PvP must not dominate or replace the core prospecting loop

---

## Timing

PvP occurs at **end of day**, after all turns have been spent.

This keeps the core prospecting loop intact and fast. Players do not interrupt each other's turns.

---

## Structure

### Phase 1 — Break-In

The attacker selects a target and attempts to gain access to their operation.

### Phase 2 — Action

The attacker chooses an action:

| Action | Risk | Potential Reward |
|---|---|---|
| **Pilfer** | Low | Small scrap gain |
| **Confront** | Higher | Moderate scrap gain |

### Phase 3 — Resolution

Outcome is determined by the engine.

| Result | Attacker | Defender |
|---|---|---|
| **Win** | Moderate scrap gain | Small scrap loss |
| **Lose** | Small scrap loss + hospital | Nothing |

---

## Hospital

The hospital is a **narrative consequence system** and a **press-your-luck mechanic**.

### Duration

A hospital stay lasts until the **attacker logs back in and has new turns**.

This means:
- If you lose a PvP confrontation, you are sidelined until your attacker returns
- The attacker's login cadence determines your downtime
- There is no fixed duration; it is socially determined

### Effect

If a player loses combat:
- They have **no more actions for the day**
- They **cannot attack anyone else**
- They may suffer small mechanical penalties (exact penalties TBD)

### Design Intent

Hospital is not meant to be punitive. It is meant to:
- Make PvP feel consequential
- Create a **second press-your-luck layer**: the attacker gambles that the target's defenses are weak; the target gambles that no one will attack them while they are logged out
- Tie downtime to player behavior rather than arbitrary timers

---

## Target Selection

Players **cannot attack someone who is actively logged in.**

This creates a social dynamic: if you stay logged in, you are safe. If you log out, you become a potential target. It also prevents real-time harassment — no one can be attacked while they are playing.

### Open Question

How exactly did Funeral Quest handle this? Research FQ's exact login-detection and target-eligibility mechanics before finalizing.

### Candidate Target Pools

- Players who have logged out and have unused turns
- Leaderboard neighbors (nearby rank)
- Players with above-average scrap (higher reward, higher risk)

---

## Success Determination

Outcome is determined by **attacker stats vs. target defenses**, with a random component.

- **Attacker stats** — operational capability, equipment, reputation (exact stats TBD)
- **Target defenses** — passive defenses set by the target player (e.g., security investment, base layout)
- **Random roll** — a chance element so outcomes are never fully deterministic

The formula needs refinement. Character upgrades and stat definitions are future scope; see [README](README.md) Future-Scope Resources table.

### Design Note

This is intentionally underspecified. Do not finalize the formula until character progression and defensive systems are designed.

---

## Notifications

TODO: Does the defender know they were attacked?

- **Option A:** Defender receives a notification at next login ("Someone tried to break in last night.")
- **Option B:** Defender only notices if scrap is missing
- **Option C:** No notification; the world is indifferent

---

## Defensive Play

Defenses are **passive and non-interactive** for the target player.

- The target does not respond in real time
- The target does not make active choices during an attack
- Defenses are set beforehand (e.g., through upgrades, base layout, or security investment)
- The attacker faces the target's **prepared defenses**, not the player themselves

This keeps PvP asynchronous and avoids requiring both players to be online simultaneously.

---

## Balance Rules

- PvP redistributes value; it does not generate new value
- No player should be driven to zero scrap by repeated PvP losses
- Leaderboard rank must not be dominated by PvP outcomes
- Hospital penalties must be felt but not fun-destroying
- A player who ignores PvP entirely must still be able to win the season

---

## Implementation Notes

### Design Constraints

- Player interaction remains indirect except for limited PvP
- No real-time coordination required
- No cooperative mechanics required
- Backend handles PvP outcome resolution

### From MVP 1.0

PvP was explicitly excluded from the MVP. It is a post-MVP feature.

### Database Trigger

> Move to MariaDB when: multiple active users, PvP added, state grows complex.

PvP requires persistent cross-player state (who attacked whom, hospital status, scrap transfers). The current JSON file state may be insufficient once PvP is active.

---

## YAML Content

TODO: PvP events and outcomes may eventually be defined in YAML:

```yaml
id: pvp_confrontation_001
type: pvp
tags:
  - pvp
  - confrontation

text: >
  You slip through the outer perimeter.
  Inside, you find a device half-dismantled on a workbench.
  The owner is asleep in the next room.

actions:
  - id: pilfer
    label: Take what you can and leave
    risk: low
    outcome: pvp_pilfer_resolve

  - id: confront
    label: Wake them and demand more
    risk: high
    outcome: pvp_confront_resolve
```

---

## Resolved

- **Target selection** — Cannot attack logged-in players (Funeral Quest pattern). Need to research FQ's exact mechanics.
- **Success formula** — Attacker stats vs. target defenses + random roll. Exact formula TBD.
- **Defensive mechanics** — Passive, non-interactive defenses set by target beforehand.
- **Hospital duration** — Until attacker logs back in with new turns. Loser loses remaining daily actions and cannot attack.

## Open Questions

1. **Scrap floor** — is there a minimum scrap a player cannot lose below?
2. **Attack frequency** — once per day? Once per season? Cooldown-based?
3. **Leaderboard visibility** — do players know who attacked them? Can they retaliate?
4. **Narrative tone** — should PvP be described as theft, sabotage, competitive rivalry, or something else? See [Tone Guide](Tone%20Guide.md).
5. **Stat definitions** — which player stats affect PvP? Character upgrades are future scope; see [README](README.md) Future-Scope Resources table.
6. **Defensive options** — what can a player invest in to improve their passive defenses?
7. **Funeral Quest research** — review FQ's exact login-detection, target pools, and PvP outcome logic.
