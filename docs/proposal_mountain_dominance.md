# Mountain-Centered Faction Dominance Display

## Purpose

Replace the current faction registry (personal standing stars) with a
PB3K terrain-scan visualization of the Mountain that shows global faction
dominance.

The Mountain itself becomes the chart — a diegetic, low-resolution raster
display rendered by the ProspectBoy 3000's terrain scanner. Faction names
and glyphs appear alongside the scan in rank order, with position and
scan quality communicating who is winning and by how much.

## Core Concept

- **The Mountain is the chart.** A UTF-8 half-block raster (█ ▓ ░) forms
  a crude elevation profile of the Mountain. The faction list sits beside
  it in rank order.
- **Scan quality reflects dominance margin.** When the leader is DOMINANT,
  the raster is crisp and solid. When CONTESTED, the scan is noisy and
  fragmented — faction conflict degrades the PB3K's terrain reading.
- **Rank order tells the story.** The dominant faction at the top, weaker
  factions below. No pixel-position mapping needed.
- **Clickable glyphs.** Every faction icon and name opens the faction
  reference sheet in the secondary panel via `data-reference-id`.

## Design Goals

- Make the Mountain visually present as the center of the fictional world.
- Make faction dominance immediately legible without reading percentages.
- Give the existing faction iconography (SVG glyphs) more prominence.
- Show that faction standing changes over time (daily scan variation).
- Reinforce that all five factions compete over the same source of power.
- Prefer symbolic/qualitative information over precise numerical data.
- Fit the PB3K terminal aesthetic — amber-on-black, chunky, monospace.
- Survive mobile: raster compresses to a 3-char strip, names abbreviate.

## Scan Quality by Tier

| Tier | Distribution | Visual |
|------|-------------|--------|
| CONTESTED | 25% █ 35% ▓ 40% ░ | Heavy noise, fragmented |
| LEADING | 45% █ 35% ▓ 20% ░ | Some noise, fuzzy |
| STRONG | 70% █ 25% ▓ 5% ░ | Stable, mostly solid |
| DOMINANT | 90% █ 10% ▓ 0% ░ | Crisp, clear summit |

## Implementation Architecture

- `DominanceService` → `ranked_factions`, `_build_raster`, `_mountain_shape`
- `FactionsController` → fragment handler uses dominance data + raster
- `HomeController` → compact "TOP SALES" line at dashboard bottom
- New template: `templates/factions/mountain_chart.html.ep`
- CSS: `.mm-mountain-*` classes with mobile breakpoint
- Click-to-reference: reuses existing `data-reference-id` mechanism
