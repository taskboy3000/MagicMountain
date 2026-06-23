---
tags:
  - push-model
  - mechanics
---
# Magic Mountain — Artifact Mechanics (v1.0)

*Last updated: 2026-05-24*

*Source documents merged: Push/Stop Design Decision, Collapse Curve Adjustments,
Push Math Model v0.2, Artifact Definitions v0.1. Artifact narrative content
lives in `content/artifacts/*.yml` — this document describes the system.*

## Purpose

This is the canonical reference for artifact processing mechanics. It defines the
push/stop interaction model, the collapse curve, evolution/breakthrough, state
thresholds, and the API contract.

---

## 1. Design Decisions

### Why Push/Stop Only

Earlier designs considered multi-tier actions (light / push / force). These were
removed because:

- Multiple risk buttons reduce clarity of player intent
- Tiered actions make the system feel mechanical
- They weaken interpretation-based gameplay
- The player should create risk by choosing to continue, not by selecting an
  explicit risk level

The player has only two actions:

- **Push** — continue working on the artifact
- **Stop** — cash out and secure value

### Why Option B (Linear Dampened)

The original analysis preferred an exponential curve:
`collapse_chance = (instability / max_instability) ^ 1.5`

However, **Option B** was chosen for implementation:

```
collapse_chance = max(0.05, (instability / max_instability) * 0.8)
collapse_chance = min(1.0, collapse_chance)
```

This is a linear dampening (× 0.8) with a 5% safety floor and 100% ceiling.

Reasons for choosing Option B:
- Simpler to reason about and tune
- 5% floor guarantees early pushes are never completely safe
- 100% ceiling guarantees late-stage collapse is certain
- The emotional effect ("I think I can get one more") is preserved
- Minimal implementation complexity

---

## 2. Core Interaction

### Push

The player continues working on the artifact.

A push may:
- increase the artifact's value
- increase the artifact's instability
- trigger a breakthrough (evolution)
- cause collapse

### Stop

The player cashes out.

Stopping:
- converts current artifact value into scrap and score
- clears the current artifact
- has no risk

---

## 3. Core Variables

Each active artifact instance tracks:

| Field | Description |
|---|---|
| `id` | Artifact type ID (links to YAML content) |
| `value` | Current cash-out value |
| `instability` | Current instability level |
| `max_instability` | Instability cap for this artifact type |
| `stage` | Player-facing state: `stable` / `strained` / `unstable` |
| `push_count` | Number of pushes this session (for logging/tuning) |
| `can_evolve` | Whether this artifact has breakthrough potential |
| `has_evolved` | Whether breakthrough has already triggered (guards against repeats) |
| `evolution_threshold` | Ratio of instability/max_instability at which evolution becomes possible (default: 0.50) |
| `evolution_chance` | Probability of evolution triggering when threshold is met (default: 0.08) |
| `evolution_instability_spike` | Instability added on evolution (default: 3) |
| `breakthrough_multiplier_min` | Minimum value multiplier on evolution (default: 1.5) |
| `breakthrough_multiplier_max` | Maximum value multiplier on evolution (default: 2.5) |
| `instability_growth_min` | Minimum instability increase per push (default: 1) |
| `instability_growth_max` | Maximum instability increase per push (default: 3) |
| `base_gain_min` | Minimum value increase per push (default: 2) |
| `base_gain_max` | Maximum value increase per push (default: 5) |
| `state_thresholds` | Per-artifact overrides for stage boundaries (default: stable ≤0.30, strained ≤0.65) |

Notes:

- `evolution_threshold` is a **ratio** (0.0–1.0), not an absolute instability value.
- `stage` is used in code and API responses. The Math doc v0.2 incorrectly used `state`.
- YAML may define any of these parameters. See `content/artifacts/`.

---

## 4. Push Resolution Order

Each push resolves in this order:

1. Increase instability by a random amount within growth range
2. Update artifact `stage` from ratio-based thresholds
3. Check for collapse (probabilistic, dampened linear)
4. If not collapsed, check for evolution/breakthrough
5. If no breakthrough, apply normal value gain
6. Return updated artifact state to client

---

## 5. Collapse Mechanics

Collapse means the artifact is lost.

Collapse should:

- clear the artifact
- award no value
- return collapse text from YAML
- award zero salvage (for MVP)

Do not apply:

- player damage
- turn loss
- long-term penalty

Failure should cost opportunity, not punish the player directly.

### Formula

```perl
my $ratio = $artifact->{instability} / $artifact->{max_instability};
my $collapse_chance = $ratio * 0.8;
$collapse_chance = 1.0 if $collapse_chance > 1.0;
$collapse_chance = 0.05 if $collapse_chance < 0.05;

if (rand() < $collapse_chance) { ... collapse ... }
```

---

## 6. Evolution / Breakthrough

Some artifacts have latent high-value potential.

When evolution triggers:

- value increases sharply (multiplied by random value within breakthrough range)
- instability increases sharply (evolution_instability_spike)
- the artifact is auto-stopped (player must decide whether to start again)
- the artifact becomes more tempting but more dangerous

For MVP, evolution happens **at most once per artifact** (`has_evolved` flag prevents repeats).

Future scope: progressive evolution stages with increasing thresholds,
multipliers, and instability spikes. Each stage would auto-stop and let the
player decide whether to start again.

---

## 7. State Thresholds

Stages are determined as fractions of `max_instability`:

```
if ratio <= state_thresholds.stable:      stage = "stable"
else if ratio <= state_thresholds.strained: stage = "strained"
else:                                         stage = "unstable"
```

Default thresholds:

- **stable** — ≤ 0.30 of max_instability
- **strained** — ≤ 0.65 of max_instability
- **unstable** — > 0.65 of max_instability

Per-artifact overrides are defined in YAML under `state_thresholds`.

The `stage` controls player-facing signal text (drawn from YAML). The client
should not display exact instability numbers.

### Signal Design Rationale

Signals are the player's only window into artifact instability.

The design replaces explicit state labels (`[Stable]`, `[Strained]`,
`[Unstable]`) with narrative flavor text. Goals:

- Preserve internal state clarity for the system
- Remove explicit labels from the player experience
- Communicate risk through narrative signals
- Create ambiguity and tension

### Implementation

The system tracks `stable` / `strained` / `unstable` internally for logic.
Each `stage` maps to a pool of flavor text in the artifact's YAML (`signals:`).
One line is selected randomly and returned with each push response.

The player never sees exact instability numbers or explicit stage labels.

---

## 8. Suggested MVP Defaults

```yaml
defaults:
  base_value: 5
  starting_instability: 0
  max_instability: 12

  instability_growth_min: 1
  instability_growth_max: 3

  base_gain_min: 2
  base_gain_max: 5

  evolution_threshold: 0.50
  evolution_chance: 0.08
  evolution_instability_spike: 3

  breakthrough_multiplier_min: 1.5
  breakthrough_multiplier_max: 2.5

  state_thresholds:
    stable: 0.30
    strained: 0.65
```

---

## 9. Response Shapes

### Normal Push

```json
{
  "ok": true,
  "result": "push",
  "artifact": {
    "id": "thermal_box_001",
    "stage": "strained",
    "value": 15,
    "signal": "The casing flexes slightly."
  },
  "player": {
    "name": "joe",
    "turns_remaining": 9,
    "scrap": 22,
    "score": 22
  }
}
```

### Breakthrough

```json
{
  "ok": true,
  "result": "breakthrough",
  "reward": 45,
  "message": "Something new emerges from the device.",
  "player": {
    "name": "joe",
    "turns_remaining": 9,
    "scrap": 67,
    "score": 67
  }
}
```

### Collapse

```json
{
  "ok": true,
  "result": "collapse",
  "message": "The unit cracks once and goes cold.",
  "reward": 0,
  "player": {
    "name": "joe",
    "turns_remaining": 9,
    "scrap": 22,
    "score": 22
  }
}
```

### Stop

```json
{
  "ok": true,
  "result": "stop",
  "value_converted": 27,
  "message": "Artifact secured.",
  "sale_text": "A trader pays for a reliable heat source.",
  "player": {
    "name": "joe",
    "turns_remaining": 9,
    "scrap": 49,
    "score": 49
  }
}
```

---

## 10. Design Constraints

- UI must expose only Push and Stop
- No Light / Push / Force tiers
- No explicit risk percentages shown to the player
- No guaranteed safe number of pushes
- Collapse must feel like overreach, not random punishment
- Breakthroughs should be rare enough to feel special
- Breakthroughs should increase both value and danger
- The server owns all math and outcomes
- YAML may define parameters and text, but game rules live in code

---

## Guiding Principle

The player creates risk by continuing.

The artifact becomes more valuable and more dangerous at the same time.
