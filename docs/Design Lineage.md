---
tags:
  - vision
  - loop
  - push-model
---
# Magic Mountain — Design Lineage

*Last updated: 2026-05-24*

## Why Fixed Turns?

Brief history of browser strategy action-economy models:

1. **PBEM / turn-based empires** (mid-1990s) — discrete turns played via email or web forms
2. **Regenerating turns** (Utopia, Earth: 2025) — turns accumulate over real time
3. **Energy systems** (Mafia Wars, FarmVille) — a cap-and-drain resource that powers actions
4. **Tick systems** (Planetarion) — the entire world advances on a fixed clock
5. **Queue systems** (Travian, Ikariam) — players schedule actions that resolve later
6. **Cooldown systems** (modern idle games) — each action has its own timer

Magic Mountain chose **fixed turns** (10/day) because:
- Scarcity creates meaning (every turn matters)
- Daily rhythm encourages return visits
- Prevents energy-system "binge then wait" pacing
- Aligns with the 3–10 minute session target

## The Five Addictive Traits

Successful browser strategy games share:

1. **Persistent progress** — your state exists while offline
2. **Scarce actions** — every turn is a real decision
3. **Asynchronous competition** — leaderboard, not head-to-head
4. **Long-term planning** — season structure creates delayed consequences
5. **Social politics** — future scope, but leaderboard seeds it early

Magic Mountain intentionally pursues all five.

## Lessons from Funeral Quest

FQ validated several specific patterns:

| FQ Pattern | Magic Mountain Equivalent |
|---|---|
| "Wait for customer" backbone action | Prospecting (extract artifact) |
| Turn-consuming vs free events | Prospecting turns vs future interrupt events |
| Customer mood/resistance/spending | Artifact instability/signals/push-your-luck |
| Daily newspaper modifiers | Seasonal environmental flavor (future scope) |
| HTTP polling architecture | Same — no real-time required |
| Security warning (old infra unsafe) | Don't copy FQ's server patterns |

## The Intended Rhythm

> Log in. Use your turns. Make progress. Come back tomorrow.

This is the core emotional loop. The game should never feel like work or a commitment. It should feel like checking in on something that matters.

## Note on Terminology

"Prospecting" was the original player-facing verb (FQ's "wait for customer" = "prospect artifact"). The current UI and code use "start artifact" for simplicity. Both refer to the same action.
