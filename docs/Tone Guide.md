---
tags:
  - tone
  - ux
---
# Magic Mountain — Tone Guide (v1.0)

*Last updated: 2026-05-24*

*Source documents merged: Narrative Tone & Writing Guide v0.2, Tone Invariants (Operational), Design Drift Detection & Invariants v0.1.*

## Purpose

This document defines the narrative tone, writing style, and design invariants for
all Magic Mountain content. It is intended for human writers, LLM content
generators, and design reviewers.

Tone rules should guide writing without eliminating ambiguity or creativity.

---

## 1. Emotional Targets

Each event should land somewhere in this range:

- curiosity
- unease
- dry amusement
- recognition
- quiet discomfort

Never:

- shock for its own sake
- cruelty as entertainment
- gleeful darkness

---

## 2. Narrative Philosophy

### Core Narrative Intent

Write about ordinary people pursuing ordinary ambitions in a world whose inherited machinery and temporary opportunities make ordinary behavior look strange.

Show how ordinary people behave under pressure, scarcity, and uncertainty—without judging them.

The game is not satire in the sense of mocking people. It is observational.

- People act
- Systems respond
- Consequences emerge

The player is not taught. The player notices.

### World Tone

The setting is post-apocalyptic from the reader’s perspective. But it should not be psychologically post-apocalyptic for most characters.

They were born here. Their parents were born here. Their inherited institutions, prejudices, trades, faiths, jokes, debts, recipes, small ambitions, and civic irritations developed long after whatever ended the prior world.

They do not think:

> We are survivors of the Fall.

They think:

> Rent is high because everyone came for the Mountain.

Or:

> Do not buy water east of the shrine after noon.

Or:

> My sister married someone who repairs Mountain junk, and now she thinks she is important.

The world is grounded:

- No one believes they are absurd
- Everyone believes their actions make sense
- Desperation drives behavior

Absurdity is never acknowledged by characters. Only observed by the player.

Characters exist across a spectrum of desperation:

- hopeful
- opportunistic
- fearful
- resigned
- desperate

The tone shifts based on environment and events.

### Player Role

The player is an opportunist in a temporary system.

Not a hero, savior, or villain.

They take risks, pursue advantage, make tradeoffs.

The game presents choices. It does not assign identity.

---

## 3. Writing Style

### Narrative Style

**Length**

- short (3–6 sentences typical)
- high signal
- no filler

**Structure**

1. Situation
2. Context (optional hint)
3. Player choice
4. Outcome

**Density**

- most events: very short
- occasional standout events: slightly longer
- no long cutscenes

Respect the player's attention budget.

### Language Style

The voice should be:

- clear
- restrained
- slightly dry
- observational

Avoid:

- dramatic flourish
- moral language
- exaggerated emotion

**Example Voice**

Bad: "The desperate villagers beg you for help."

Good: "The villagers have organized a queue. No one seems sure what the queue is for."

### Humor Philosophy

Rule: Humor must never reward cruelty.

The tone should align with: *Brazil*, *Twelve Monkeys*, *Heathers* (upper bound: *Fight Club*).

Avoid:

- sadistic humor
- exploitation-as-punchline
- "isn't suffering funny"

Humor emerges from people behaving rationally inside irrational systems.

Example: A man is selling "verified safe water." He drinks from every container to prove it. He looks unwell. No joke is told. The situation is the humor.

The player may profit from situations. They should not be encouraged to enjoy harm.

### Violence & Menace

Violence exists, but is treated carefully.

Tone: grounded, consequential, uncomfortable when noticed.

Avoid:

- cartoon violence
- gore
- spectacle

Prefer:

- implication
- aftermath
- restraint

**Example**

Bad: "The raiders butcher everyone."

Good: "The road is quiet. The carts are still there. No one is guarding them."

Violence should feel like a cost, not a feature.

### Suggestion Over Explanation

Leave space for the player to think.

Avoid:

- explaining motivations fully
- resolving ambiguity
- over-describing systems

Use:

- implication
- contradiction
- incomplete information

**Example**

"The machine hums louder when ignored. No one has tested this twice."

---

## 4. Artifact Text Rules

### Allowed Characteristics

Text should:

- describe observable behavior (heat, motion, sound, pattern)
- remain grounded in physical or sensory detail
- avoid explaining what the artifact "is for"
- allow multiple interpretations

### Disallowed Characteristics

Text must NOT:

- explicitly identify the object (e.g., "heater", "gun", "computer")
- explain purpose or intended use
- include modern terminology (AI, app, UI, software, interface)
- include jokes, sarcasm, or meta commentary
- directly instruct the player how to interpret the artifact

### Preferred Writing Style

Good examples:

- "The heat is steady."
- "A faint rhythm emerges, then falters."
- "The surface shifts when you look away."

Bad examples:

- "This looks like a heater."
- "The device is malfunctioning."
- "You should stop before it breaks."
- "This reminds you of a computer display."

### Ambiguity Requirement

Each artifact description should:

- support at least two plausible interpretations
- avoid resolving uncertainty completely
- allow the player to form their own conclusion

### Signal Quality Rules

Signals should:

- suggest increasing instability without stating it directly
- vary slightly within the same state
- occasionally mislead (false confidence is allowed)

Example:

- acceptable: "The output stabilizes briefly."
- unacceptable: "The artifact is now stable."

---

## 5. LLM Validation Rules

A text FAILS validation if:

- it names a real-world object category
- it explains function instead of behavior
- it uses modern or technical jargon
- it contains humor or meta commentary

A text PASSES validation if:

- it describes behavior only
- it maintains ambiguity
- it fits within the tone examples above

---

## 6. Design Invariants

### Core Loop Invariants

- Player has only two actions: Push and Stop
- Risk is created by continuing, not selected explicitly
- There is no guaranteed safe number of pushes

### Player Experience Invariants

- Player must feel uncertainty
- Player must interpret artifact behavior
- Player must sometimes misjudge risk
- Player should feel ownership of failure

### Artifact Invariants

- Artifacts are never explicitly identified
- Text describes behavior, not purpose
- Multiple interpretations must remain valid

### Failure Model Invariants

- Failure removes opportunity, not agency
- No direct punishment beyond artifact loss
- Core loop failure (artifact collapse) does not remove turns, health, or long-term penalties
- PvP outcomes are a separate system and may consume remaining daily actions (see [PvP Combat](PvP%20Combat.md) §Hospital)

### Tone Invariants

- grounded and restrained
- slightly uncanny
- no modern or meta references
- no overt humor that breaks immersion

---

## 7. Drift Detection

### Three-Layer System

Design Invariants → LLM Validation → Human Review

### Flavor Drift Signals

Flag if text contains:

- explicit object names (heater, gun, computer)
- modern terminology (AI, app, interface)
- jokes or sarcasm
- overly explanatory language

### Design Drift Signals

Flag if code introduces:

- multiple risk buttons
- explicit probability display
- guaranteed outcomes
- reward systems not tied to pushing

### Play Transcript Review

Use actual gameplay logs to validate experience.

**Example Log**

Turn 1: push → signal  
Turn 2: push → signal  
Turn 3: breakthrough  
Turn 4: collapse

**Review Prompt**

Given this play sequence:

- Does tension increase over time?
- Is there ambiguity in signals?
- Is there a meaningful moment of regret or surprise?

Return PASS/FAIL with reasoning.

### Golden Path Check Loop

A simple repeatable workflow:

1. Extract artifact YAML
2. Run flavor validation
3. Extract game logic
4. Run system validation
5. Review any violations
6. Optionally review play transcript

Run this after adding new artifacts, after modifying push logic, or before
declaring a milestone complete.

**Important Constraints**

- Do not over-automate tone validation
- Do not block creative writing with rigid rules
- Use LLM checks as signals, not absolute truth

---

## 8. Content Boundaries

Avoid:

- sadism
- glorified cruelty
- nihilism
- modern meme tone
- explicit moral instruction

Encourage:

- ambiguity
- irony
- unintended consequences
- human behavior under pressure

---

## 9. World-Building Tone

### Faction Tone

Factions represent real human impulses.

Each faction contains:

- true believers
- opportunists
- skeptics

**Religious Expression**

Handled with care:

- belief is sincere for some
- useful for others
- confusing for many
- A player may not understand why a character has faith, but other characters will understand

Avoid:

- mockery
- explicit endorsement
- simple "they are wrong" framing

Every belief system must feel internally coherent.

---

## 10. Season & Environment Tone

### Environmental Tone Integration

Each season's condition influences:

- mood
- NPC behavior
- event framing

Not just mechanics.

**Example**

Drought season:

- shorter tempers
- faster decisions
- less long-term thinking

Environment shapes behavior, not just outcomes.

### End-of-Season Narrative

This is the one place where narrative expands.

Tone should be:

- reflective
- observational
- slightly historical

**Structure**

- what happened
- what changed
- what consequences followed

Report history. Do not interpret it.

---

## Guiding Principle

The player should feel:

> "I can see what it does, but I do not know what it is."

You cannot test "fun". You can test whether the system preserves ambiguity,
whether risk is player-driven, and whether the world remains interpretable.

Protect this core experience:

> The player is interacting with something real, but does not fully understand it, and must decide how far to push anyway.

---

*If you need one sentence to guide writing:*

Write as if documenting a strange but believable society where everyone is trying to make sense of something they don't understand—and make a living while doing it.
