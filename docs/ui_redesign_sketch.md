# UI Redesign Sketch — ProspectBoy 3000 Device Layout

## Outer Frame

```
┌─────────────────────────────────────────────────┐  ← device bezel
│  THE PROSPECTBOY 3000 // LOCAL NODE 07           │  ← device header (pinned)
│  DAY 12/30   AP 5   SCRAP 184   SCORE 311        │  ← status strip (pinned)
├─────────────────────────────────────────────────┤
│  ┌──────────┐ ┌──────────┐ ┌──────────┐         │  ← nav bar (pinned below status)
│  │ PROSPECT │ │  SHED    │ │  MARKET  │ ...     │
│  └──────────┘ └──────────┘ └──────────┘         │
├─────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────────┐          │  ← active panel area
│  │  Activity     │ │  Secondary info   │         │     (scrollable internally)
│  │  panel        │ │  (shed/factions/  │         │
│  │               │ │   leaderboard)    │         │
│  │               │ │                   │         │
│  └──────────────┘ └──────────────────┘          │
├─────────────────────────────────────────────────┤
│  [PROSPECT][STOP][PUSH]    FACTION: SYNDICATE    │  ← context bar (pinned bottom)
└─────────────────────────────────────────────────┘  ← device bezel
```

## Component Tree

```
#device-frame                          (fixed max-width + max-height, centered)
  #device-header                       (top row — device name/version)
  #status-strip                        (day, AP, scrap, score — grid cells)
  #nav-bar                             (horizontal buttons — terminal tab style)
  #main-area                           (flex row, overflow hidden)
    #panel-primary                     (flex: 2 — current activity)
    #panel-secondary                   (flex: 1 — context panel)
  #context-bar                        (bottom — action help / faction pulse)
```

## Panel Swap Rules

Each nav button selects which "app" is active in `#panel-primary`:

| Nav Button | Primary Panel | Secondary Panel |
|-----------|---------------|-----------------|
| PROSPECT | Prospecting scan | Shed summary |
| SHED | Full shed ledger | Factions pulse |
| MARKET | Market negotiation | Factions pulse |
| FACTIONS | Faction registry | Leaderboard |
| SKILLS | Training records | — |
| BULLETIN | Crier feed | — |

When an activity forces focus (expedition started, market visit begun), the nav auto-switches to `PROSPECT` or `MARKET` and `#panel-secondary` shows whatever is relevant.

## Responsive Behavior

**Desktop (≥900px):** Both panels side by side. `#device-frame` is centered with a fixed width cap (~48rem) so it looks like a device screen, not a full-width page.

**Tablet (600-899px):** Both panels side by side but narrower. Primary gets ~60%, secondary ~40%.

**Phone (<600px):** Single panel mode. `#panel-secondary` is hidden. Nav bar buttons switch between views (primary cycles through all panel types). Secondary info becomes a toggleable overlay or pushes primary out of view.

No horizontal scroll. Everything either fits in the frame or scrolls vertically within its panel.

## Visual Details

- All panels share a single outer border (the device frame). No panel-on-panel borders — use subtle background alternation (`--mm-panel` vs `--mm-panel-2`).
- Separators use box-drawing characters (──, │, ──, ├ ┤) in the device chrome, not in content.
- Status strip uses fixed-width columns aligned with tab stops (┌─────┬─────┬─────┐ style via CSS grid with monospace ch units).
- Nav bar buttons use `[ LABEL ]` bracket styling via CSS pseudo-elements.
- Context bar at the bottom shows contextual shortcuts, like "TAB to switch panels" or faction mood.
- The device frame background (`--mm-black`) extends slightly past the content border to create a subtle bezel effect on the `body` background.

## Migration Path

1. Add `#device-frame` wrapper around the existing content in `game/show.html.ep`.
2. Extract the header/status/nav into pinned elements at top.
3. Wrap center area into the two-panel flex container.
4. Move each fragment endpoint to render into `#panel-primary` or `#panel-secondary` as appropriate.
5. Add CSS for the frame, bezel, nav bar, status grid, and context bar.
6. Remove the stacked vertical layout CSS.
7. Add nav-switching JS to `game.js`.
