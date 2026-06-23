---
tags:
  - architecture
  - state
---

*Last updated: 2026-05-24*

## Purpose

This document describes the high-level technical architecture of the game.

It defines:
- how the client and server are structured
- where game logic lives
- how systems are organized

It does not define:
- specific frameworks
- implementation details
- database schemas

---

# Architecture Overview

The game uses a **server-authoritative client/server model**.

## Core Principle

- The **server owns all game state and outcomes**
- The **client presents information and captures player intent**

Players compete within a shared seasonal world, so all outcomes must be resolved server-side.

---

# Server-Side Module Composition

The backend is organized around a small set of focused Perl modules. The intent is to keep game rules, persistence, and coordination in separate layers so that future changes (for example, replacing JSON file storage with MariaDB) touch only one boundary.

```text
Api / CLI / Simulate
        │
        ▼
   ┌─────────┐
   │ Engine  │  ← per-request coordinator
   └────┬────┘
        ├──→ State      (JSON read/write/lock, structural defaults)
        ├──→ Turn       (artifact push/collapse/breakthrough math)
        ├──→ Content    (YAML loading, weighted selection)
        └──→ Transcript (optional JSONL event recording)
```

## Module Responsibilities

| Module | Role |
|---|---|
| `Engine` | Single entry point for all game operations. Owns the per-request lifecycle: reload state, apply daily rollover, delegate to domain objects, persist. |
| `State` | Owns the JSON file, `flock`-based locking, and structural initialization (for example, ensuring `season.day` exists). Does not contain game rules. |
| `Turn` | Owns artifact mechanics: validating state, running push/collapse/breakthrough math, recording transcript events. Does not save state or handle rollover. |
| `Content` | Loads YAML artifact definitions and performs weighted random selection. |
| `Transcript` | Opens a JSONL file per session and records structured game events (`push`, `collapse`, `stop`, etc.). |
| `Bot` | Given an artifact hashref and a policy name, returns `"push"` or `"stop"`. Used by the simulation CLI. |

## Lifecycle

`Engine` is instantiated per-request rather than as an application singleton. This prevents state leakage between requests and aligns with Mojolicious conventions for holding per-request resources such as a future database connection.

Construction pattern:
```perl
my $engine = MagicMountain::Engine->new(
    state      => $app->state,
    content    => $app->content,
    log        => $app->log,
    transcript => $transcript,  # optional
);
```

---

# Server Responsibilities

The server is responsible for:

- player state
- seasonal state
- artifact generation
- push-your-luck resolution
- event resolution
- faction influence
- PvP outcomes
- leaderboard calculation
- daily maintenance
- season resets

## Rule

> The client sends intent.  
> The server resolves consequence.

---

# Client Responsibilities

The client is responsible for:

- rendering UI
- presenting narrative text
- handling player input
- playing sound effects
- lightweight animation
- displaying game state

The client should not:

- calculate outcomes
- determine success/failure
- modify authoritative game state

---

# Frontend Approach

The game should be built using standard web technologies:

- HTML
- CSS
- JavaScript

## Design Direction

- No canvas required
- No 2D/3D engine required
- Focus on **document-style UI**

This should feel like:

> an interactive illustrated web interface

Not:

> a traditional animated game engine

---

# UI Structure

A typical play screen may include:

- world message / narrative text
- turns remaining
- current event panel
- artifact state (signals / description)
- player choices (push / stop / event options)
- daily summary
- leaderboard access

---

# Interaction Loop (Frontend)

```text
Artifact appears
→ player pushes or stops
→ signals update
→ outcome resolves
→ next event

## Social Systems

The game does not require built-in real-time chat.

Players may compete in the same seasonal world without direct communication.

## Design Rationale

The game is built around:
- asynchronous play
- individual optimization
- leaderboard pressure
- indirect world influence

Direct chat is not part of the core loop.

## Cooperative Play

The game should not encourage cooperative play as a primary mode.

Players may share a world, influence factions, and compete on leaderboards,
but the main experience remains individual and competitive.

## External Socialization

If players want to socialize, they can be directed to external community spaces.

Examples:
- Discord
- forums
- comments/community page

These should remain outside the core game loop.

## Design Constraints

- no real-time chat required for prototype
- no cooperative mechanics required
- no multiplayer coordination required
- player interaction remains indirect except for limited PvP

## Mobile-Friendly Design

The game should be designed to support mobile clients without requiring a separate backend.

## Core Principle

The backend must be usable by multiple client types:

- browser-based client (primary)
- future mobile client (iOS or Android)

All game logic must be independent of presentation.

## API Design

The server should expose game actions through structured endpoints.

Examples:

- fetch player state
- resolve turn
- push artifact
- stop processing
- resolve event choice
- attempt PvP
- fetch leaderboard

All endpoints should return structured data (JSON).

The browser client may use these endpoints directly or through server-rendered views.

## Separation of Concerns

Game systems must be isolated from UI rendering.

```text
Game Engine Logic (Engine / Turn / State / Content)
    -> used by web routes (HTML)
    -> used by API routes (JSON)
    -> used by CLI commands (simulate, next-day)