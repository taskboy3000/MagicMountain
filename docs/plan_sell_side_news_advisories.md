# Plan: Sell-Side NEWS + Sharper Headings + New Advisories

---

## Overview

Three related changes to the player dashboard, all driven by existing `faction_climate` data:

| Part | What | Why |
|------|------|-----|
| **A** | Replace the NEWS hint with data-driven sell-side info | Players should know what to *sell* to the dominant faction |
| **B** | Rename headings to split prospecting vs selling visually | "PROSPECT REPORT" / "BAZAAR REPORT" — clarifies the two data sources |
| **C** | Three new advisories: climate_finds, banned_trait, scrap_low | More guidance touch-points between climate data and player state |

---

## Part A: Sell-side NEWS hint

**File:** `lib/MagicMountain/Service/Dominance.pm`

**New method `_sell_side_hint($profile)`:**
- Reads `buyer_trait_biases` keys → `"Paying premium for: revelation, signal, field"`
- Reads `banned_traits` → `"Restricted: thermal, food_processing, water"`
- Joins with `; ` if both present
- Returns empty string if neither exists

**Modify `_crier_text($self, $fid, $tier, $profile)`:**
- If `_sell_side_hint` returns non-empty → `"headline — $sell_hint"`
- If empty (e.g. LibreMount: no premiums, no bans) → `"headline — [random flavor text]"` from a Perl array literal. Example entries:
  - `"Artifact values drift with the mountain's cycles. No pattern holds for long."`
  - `"Faction buyers survey the Bazaar in silence. Their intentions are their own."`
  - `"The mountain's voice is indistinct today. Listen to the scrap."`
  - `"Competing interests blur the market's shape. Trade with care."`
- Contested tier already skips `_crier_text` in the Crier (falls to daily/generic), so no separate contest handling.

**Modify `calculate_climate()`:**
- Already has `$profile` for the leader — reuse it to compute `_sell_side_hint($profile)`
- Pass `$profile` into `_crier_text`

**Tests:** Add `_sell_side_hint` subtests to `t/dominance_finds.t`. Update `t/home_web.t` to assert sell-side data appears in the rendered page.

---

## Part B: Sharper headings

| File | Current text | New text |
|------|-------------|----------|
| `templates/components/climate_card.html.ep` line 5 | `Today's Climate:` | `PROSPECT REPORT:` |
| `templates/home/dashboard.html.ep` line 8 | `NEWS:` | `BAZAAR REPORT:` |

Both stay amber (`mm-text-amber`). No behavioral change.

---

## Part C: Three new advisories

**`content/flavor/advisories.yml`** — add:

```yaml
  climate_finds: "Mountain favoring {finds_summary} — prospect now."
  banned_trait:  "Restricted items in shed: {traits}. Bazaar will refuse them."
  scrap_low:     "Scrap reserves low ({scrap}). Prospect to restock."
```

**`lib/MagicMountain/Service/Suggestion.pm`** — three new blocks added to `build()`:

| Advisory | Icon | Conditions | View | Data |
|----------|------|------------|------|------|
| Climate finds | `DRILL` | `fc.finds_summary` exists AND `ap >= prospect_cost` | prospect | `fc.finds_summary` |
| Banned warning | `LOCK` | `fc.banned_traits` non-empty AND shed behaviors intersect | bazaar | Intersection of banned_traits & shed item behaviors |
| Scrap low | `COIN` | `char.scrap < 5` | prospect | `char.scrap` |

**Order of suggestions** (position in `@suggestions`):

| Pos | Suggestion | Rationale |
|-----|-----------|-----------|
| 1 | OFFER (shed_available) | Most actionable: player has items to sell |
| 2 | DRILL (ap_available) | Next: player can prospect |
| 3 | DRILL (climate_finds) *NEW* | Climate info for prospecting — shown alongside AP-available |
| 4 | WAIT / CLOCK (idle state) | Catch-all for when player can't act |
| 5 | ALERT (season_end) | Important timing signal |
| 6 | PREMIUM (faction_hunger) | Cross-reference state |
| 7 | PREMIUM (climate_match) | Specific inventory advice |
| 8 | LOCK (banned_trait) *NEW* | Specific inventory warning |
| 9 | COIN (scrap_low) *NEW* | Resource management |

---

## Files changed

| File | Change type |
|------|------------|
| `lib/MagicMountain/Service/Dominance.pm` | Add `_sell_side_hint`, modify `_crier_text`, `calculate_climate` |
| `lib/MagicMountain/Service/Suggestion.pm` | Add 3 new blocks in `build()` |
| `content/flavor/advisories.yml` | Add 3 new template strings |
| `templates/components/climate_card.html.ep` | Heading label swap |
| `templates/home/dashboard.html.ep` | Heading label swap |
| `t/dominance_finds.t` | New subtests for `_sell_side_hint` |
| `t/home_web.t` | Update assertions for new text |
| (new) `t/advisories_suggestion.t` | Tests for new advisory blocks |
- [x] Architecture review complete
