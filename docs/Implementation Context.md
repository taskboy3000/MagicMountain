
---
tags:
  - architecture
  - state
---

*Last updated: 2026-05-24*

# Magic Mountain - Implementation Context v0.2

## Target Environment

- Single Debian 13 VM
- Approximately 4 GB RAM
- Existing server already in use
- Expected early scale: small daily player base
- No assumption of horizontal scaling

## Preferred Backend

- Perl
- Mojolicious

## Frontend

- HTML5
- CSS
- JavaScript
- No canvas engine
- No real-time game loop
- No required chat system

### Why HTTP Polling?

HTTP polling was chosen over WebSockets because real-time is not required for an asynchronous, turn-based game. This pattern was validated by Funeral Quest's architecture. See [Design Lineage](Design%20Lineage.md) for the full rationale.

## Persistence Options

**Current implementation:**

- JSON file state (`data/state.json`) with flock-based locking

**Future path:**

- MariaDB for long-term durability and admin familiarity

**Prototype path (used during early development):**

- SQLite for very early development only

## Architecture Principle

Keep the system simple enough to run comfortably on one modest VM.

## Server Responsibilities

The server owns:

- accounts
- player seasonal state
- turns
- artifact generation
- push/stop outcomes
- interrupt events
- PvP outcomes
- faction influence
- leaderboards
- daily rollover
- season reset

## Client Responsibilities

The client owns:

- display
- interaction flow
- sound effects
- visual feedback
- sending player choices to server

## Scaling Assumption

The game is asynchronous and turn-based.

This means it should not need:
- WebSockets
- real-time synchronization
- background game simulation per player
- multiple app servers at launch

## Implementation Status

The original MVP (steps 1–9) is complete. Current focus is production-ready architecture for a multiplayer, turn-based game. Server-side logic is being consolidated behind a per-request `Engine` coordinator so that the JSON state layer can be replaced with MariaDB without touching game rules. See [Technical Architecture](Technical%20Architecture.md) for module boundaries.

## Implementation Strategy

Build in small vertical slices:

1. User account / session
2. Current season state
3. Player seasonal state
4. Daily turns
5. Basic artifact prospecting
6. Push / stop resolution
7. Score and scrap updates
8. Daily reset
9. Leaderboard
10. Interrupt events
11. Faction influence
12. PvP
13. Season-end recap

## Security Notes

Funeral Quest's original server infrastructure is unsafe to run publicly. Do not copy old infrastructure patterns. Keep the current stack simple and maintainable.

## Development Constraint

Each implementation step should be small enough to hand to an LLM coding assistant as a focused task.

