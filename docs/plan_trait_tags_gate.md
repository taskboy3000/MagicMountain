# Plan: Gate Trait Tags Behind Prospecting Skill Level 1

## Context

Trait tags and the climate premium badge are currently visible to all
players from day one. Making the first prospecting skill point reveal
trait identity creates an "aha" moment and gives L1 immediate felt value.

- Climate card text ("Paying premium for: ...") stays visible day one
- Value labels (ordinary/middling/low) stay visible day one
- Only the Tags column content and the premium badge are gated
- When gated, the Tags cell shows `-` as a placeholder (hinting at
  hidden info, creating curiosity toward the skill)
- Tags column header `<th>Tags</th>` is always rendered

## Skill Level Renumbering (Straight Insert)

Current prospecting has 3 levels with hardcoded effects in Prospecting.pm:

| Level | Current Effect |
|-------|---------------|
| 1 | base_value +2 |
| 2 | base_value +2 more (total +4), weight x2 if base >= 8 |
| 3 | base_gain_min/max +1 per push = breakthrough enabled |

New 4-level layout (insert L1, shift existing down):

| Level | Cost | Effect |
|-------|------|--------|
| 1 (new) | 100 | Trait tags visible; no mechanical effect |
| 2 (was L1) | 250 | base_value +2 |
| 3 (was L2) | 500 | base_value +2 more (total +4), weight x2 if base >= 8 |
| 4 (was L3) | 1000 | base_gain_min/max +1 per push = breakthrough enabled |

Skills.yml max_level changes from 3 to 4. Descriptions shift down by
one level; new L1 description describes trait tag reveal.

Prospecting.pm renumbers its `>= 1` to `>= 2`, `>= 2` to `>= 3`,
`>= 3` to `>= 4`.

No changes to the effects themselves -- only which level grants them.

## Files to Modify

### content/skills.yml
- max_level: 3 -> 4
- Insert new level 1 description (trait tag reveal)
- Shift old level 1->2, 2->3, 3->4 descriptions and costs

### lib/MagicMountain/Activity/Prospecting.pm
- Line 40: `$prosp >= 2` -> `$prosp >= 3`
- Line 124: `$prosp >= 1` -> `$prosp >= 2`; `$prosp >= 2` -> `$prosp >= 3`
- Line 130: `$prosp >= 3` -> `$prosp >= 4`

### lib/MagicMountain/Controller/Shed.pm
- In `_enriched_items`: accept a `$skill` param (int). When skill < 1,
  set `tags` to `-` and pass `show_trait_tags => 0`. When >= 1, set
  `tags` to the joined behavior names and pass `show_trait_tags => 1`.
- The caller at line 18 must pass skill level from `$char`.

### lib/MagicMountain/Controller/Home.pm
- In the fragment path: read `skill_prospecting` from character.
  Set `tags` to `-` or joined behaviors based on skill.
  Stash `show_trait_tags => 0/1`.
- Already stashes `climate_premium_traits` from earlier work -- no
  change needed for that.

### templates/components/salvage_ledger.html.ep
- When `$show_trait_tags` is false: render `-` in the tags cell, skip
  premium badge computation.
- When true: render tags and premium badge as today.
- Guard the `$climate_premium_traits` stash lookup and badge rendering
  behind `$show_trait_tags` (badge uses `$item->{behaviors}` not
  `$item->{tags}`, so must be explicitly gated).
- Add default: `my $show_trait_tags //= 0;` at top (crash safety).

### templates/shed/ledger.html.ep
- Pass `show_trait_tags => stash('show_trait_tags')` to include.

### templates/home/dashboard.html.ep
- Pass `show_trait_tags => stash('show_trait_tags')` to include.

### GAME_ARCHITECTURE.md
- Update prospecting skill table to reflect L1-L4
- Update any flat-text references to "3 prospecting levels"
- Update skills.yml descriptions table (lines ~1070) if present

### t/skills_web.t
- Update `purchase -- already at max dies`: set skill_prospecting to 4
  (not 3), assert 400
- Update `index -- max-level skill has no upgrade action`: set
  skill_prospecting to 4, assert no upgrade action
- Update `purchase -- applied immediately` (or similar): add a 4th
  purchase step if testing incremental purchase

### t/home_web.t
- Existing tests that assert `qr/thermal/` or `qr/mm-badge-amber/`:
  set skill_prospecting=1 on the character before those assertions
- New subtest: climate card text visible when skill_prospecting=0
  (no regression)
- New subtest: tags show `-` when skill_prospecting=0

### t/shed_web.t
- Existing `climate premium badge in shed fragment`: set
  skill_prospecting=1 or badge won't render
- New subtest: tags show `-` placeholder when skill < 1
- New subtest: tags visible when skill >= 1

### bin/demo_climate
- Add `skill_prospecting => 1` to character creation

### bin/walkthrough
- In SCENE 7 (Skills), buy prospecting level 1 so the shed fragment
  assertion at lines 222-231 sees trait tags

## Tests Not Modified

- t/market_visit.t -- unaffected (no prospecting gating in market)
- t/market_visit_web.t -- unaffected
- The climate premium badge tests in market_visit.t use market skill,
  not prospecting -- no change needed

## Steps

### Step 1: skills.yml -- add L1, renumber
**Goal**: New level 1 with trait tag description, existing levels shift

### Step 2: Prospecting.pm -- renumber >= checks
**Goal**: Effects shift to L2/L3/L4, no new mechanics

### Step 3: GAME_ARCHITECTURE.md -- skill table + references
**Goal**: Document the 4-level system

### Step 4: Controllers (Home.pm + Shed.pm) -- gate tags behind skill
**Goal**: Pass show_trait_tags based on skill_prospecting

### Step 5: Templates -- conditional tags + badge
**Goal**: `-` placeholder when gated, real tags + badge when not

### Step 6: Tests -- update for new skill levels + gating
**Goal**: All existing tests pass, new gated/ungated subtests pass

### Step 7: demo_climate + walkthrough -- set skill_prospecting
**Goal**: Demo and walkthrough exercise the ungated path

### Step 8: ci-check and clean up
**Goal**: Full test suite, walkthrough, perlcritic pass; delete plan file

## What This Plan Does NOT Do

- Does NOT change Prospecting.pm mechanics (value bonuses, weight
  doubling, breakthrough) -- only renumbers which level grants them
- Does NOT change the climate card rendering
- Does NOT change value labels in the shed ledger
- Does NOT create new persistence or database tables
