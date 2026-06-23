---
tags:
  - push-model
  - loop
  - plan
---
# Magic Mountain - MVP Implementation Plan v0.1

> **Historical.** This document describes the original MVP scope. The project has since moved into production-ready architecture. Current module boundaries and server-side composition are documented in [Technical Architecture](Technical%20Architecture.md).

## Purpose

This document defines the first playable implementation of Magic Mountain.

It focuses on:
- a minimal but complete gameplay loop
- a Mojolicious backend
- a Bootstrap + fetch frontend
- JSON state storage (temporary)
- YAML-driven content

---

# MVP Scope

## Included

- login by player name (no password)
- single active season
- player state
- 10 turns per day
- artifact generation
- push / stop loop
- artifact collapse
- scrap + score
- leaderboard
- Bootstrap UI
- REST endpoints
- YAML content loading

## Excluded

- PvP
- factions
- contracts
- sound
- advanced UI
- database (MariaDB later)
- chat
- season recap

---

# Technology Stack

Backend: Perl + Mojolicious  
Frontend: Bootstrap 5 + vanilla JS (fetch)  
State: JSON file (with locking)  
Content: YAML files  

---

# Project Structure

magic_mountain/
  app.pl
  lib/MagicMountain/
    State.pm
    Player.pm
    Artifact.pm
    Turn.pm
    Leaderboard.pm
    Content.pm
  templates/
    layouts/default.html.ep
    index.html.ep
    play.html.ep
    leaderboard.html.ep
  public/
    css/app.css
    js/app.js
  data/
    state.json
  content/
    artifacts/
    text/

---

# JSON State (MVP)

{
  "season": {
    "id": "season_001",
    "day": 1
  },
  "players": {
    "joe": {
      "name": "joe",
      "scrap": 0,
      "score": 0,
      "turns_remaining": 10,
      "current_artifact": null,
      "last_seen_day": 1
    }
  }
}

---

# YAML Content

## Artifact Example

- id: thermal_box_001
  archetypes: [energy]
  behaviors: [thermal]
  weight: 10

  intro: >
    You pull free a sealed metal box.
    It is warm before you touch it.

  signals:
    stable:
      - The warmth is steady.
    strained:
      - The casing flexes slightly.
    unstable:
      - Something inside begins to tick.

  collapse:
    - The box cracks once and goes cold.

  sale:
    low:
      - Someone buys it as a hand-warmer.
    medium:
      - A trader pays for a reliable heat source.
    high:
      - A cookhouse owner takes it immediately.

## World Text Example

season_opening:
  - >
    The Mountain appeared nine days ago.
    The settlement around it formed faster than anyone planned.

daily_messages:
  - >
    The market is louder today.
    No one seems richer.

---

# REST API

POST /api/login  
GET  /api/state  
POST /api/artifact/start  
POST /api/artifact/push  
POST /api/artifact/stop  
GET  /api/leaderboard  

---

# API Response Shape

{
  "ok": true,
  "player": {
    "name": "joe",
    "turns_remaining": 9,
    "scrap": 22,
    "score": 22
  },
  "artifact": {
    "intro": "You pull free a sealed metal box...",
    "signal": "The casing flexes slightly.",
    "stage": "strained"
  },
  "message": "You push the artifact further."
}

---

# Core Gameplay Logic (MVP)

## Artifact Loop

Start Artifact:
  - consumes 1 turn
  - generates artifact from YAML
  - sets `max_instability` and `instability_growth` parameters
  - sets value = base

Push:
  - increase instability by a random amount within `instability_growth` range
  - update signal stage from ratio-based thresholds (`stable` / `strained` / `unstable`)
  - check for collapse (probabilistic, Option B formula)
  - if not collapsed, check for evolution/breakthrough
  - if no breakthrough, apply normal value gain

Stop:
  - convert value to scrap + score
  - clear artifact

Collapse:
  - lose all artifact value
  - zero salvage
  - clear artifact

---

# Backend Responsibilities

- load/save state.json
- file locking for safety
- resolve all game actions
- generate artifacts
- calculate push outcomes
- track turns + score
- return JSON responses

---

# Frontend Responsibilities

- render UI (Bootstrap)
- display artifact text + signals
- show turns, scrap, score
- send actions via fetch
- update UI from JSON response

---

# UI Layout (MVP)

---------------------------------
World Message
Turns Remaining

Artifact Card:
  Intro Text
  Signal Text

Buttons:
  [Push] [Stop] [New Artifact]

Player Stats:
  Scrap
  Score

Leaderboard Link
---------------------------------

---

# Development Steps

## Step 1: Mojolicious Setup

- create app.pl
- basic routes
- layout + Bootstrap

## Step 2: State Module

- load_state()
- save_state()
- with_locked_state()

## Step 3: Login

- POST /api/login
- session stores player name

## Step 4: Player State

- initialize player if new
- track turns_remaining, score, scrap

## Step 5: Artifact System

- load YAML
- random weighted selection
- set `max_instability` and parameter defaults
- store current_artifact

## Step 6: Push / Stop Logic

- push increments value
- random collapse check
- update signal stage
- stop converts value to score

## Step 7: UI + Fetch

- buttons trigger API calls
- update DOM from responses

## Step 8: Leaderboard

- sort players by score
- display simple table

## Step 9: Daily Reset (Simple)

- if new day → reset turns to 10

---

# JSON State Constraints

- must use file locking
- must remain small
- must not allow concurrent write corruption

Move to MariaDB when:
- multiple active users
- PvP added
- state grows complex

---

# Design Constraints

- keep loop fast
- no complex UI
- no hidden mechanics in YAML
- no real-time systems
- no premature scaling
- prioritize playable loop over completeness

---

# Guiding Principle

Build the smallest version that proves:

“Push your luck on strange artifacts is fun.”