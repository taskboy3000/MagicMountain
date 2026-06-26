Here is the finalized version to save as something like docs/design_language.md or docs/prospectboy_design_bible.md.

Magic Mountain Visual Design Language Bible

Version

v1.0 — ProspectBoy 3000 / Amber ANSI Salvage Console Direction

Purpose

This document defines the visual and interaction language for Magic Mountain’s first serious UI pass.

The goal is not to produce final art. The goal is to give the game a coherent, intentional visual identity that can guide CSS, layout, SVG icons, faction badges, UI copy, and future art direction.

⸻

1. Core Visual Concept

Magic Mountain uses a playful amber BBS/ANSI-inspired terminal frame presented through an in-world personal salvage device: The ProspectBoy 3000.

The ProspectBoy 3000 is a retro personal digital assistant for salvage operators. It is part ledger, part field scanner, part market router, part faction contact book, and part bad-decision assistant.

The player is not using a literal command-line terminal. The game remains a modern clickable browser game with clear controls, panels, buttons, tables, tooltips, tabs, and responsive layout.

The desired emotional read:

A warm amber salvage console running on old personal hardware, trying with bureaucratic confidence to classify impossible junk, unstable markets, and social factions it barely understands.

The visual style should feel:

* amber
* readable
* playful
* slightly obsolete
* salvage-business-oriented
* old-hardware-adjacent
* BBS/ANSI-inspired
* lightly funny
* not grimdark
* not clownish
* not a literal terminal emulator

⸻

2. The ProspectBoy 3000

2.1 In-World Role

The ProspectBoy 3000 is the player’s personal salvage-business assistant.

It manages:

* Mountain prospecting
* artifact scanning and valuation
* Shed inventory
* market visits
* customer routing
* counter-offers and sale records
* faction contacts
* faction standing
* Crier bulletins
* skill/training records
* leaderboard status
* seasonal archive reports

It should feel like a retro PDA / field ledger / salvage console hybrid.

The ProspectBoy 3000 is portable, practical, slightly outdated, and more confident in its classifications than it ought to be.

2.2 What It Is Not

The ProspectBoy 3000 is not:

* a literal terminal emulator
* a fake shell
* a wrist-mounted survival computer
* military hardware
* vault equipment
* a parody of another game’s UI
* a command-line-only interface
* a grimdark surveillance device

It is a salvage-business assistant for opportunists.

2.3 Naming and Configurability

The default device name is:

The ProspectBoy 3000

This name should be configurable because the surrounding fiction may evolve.

Example config:

ui:
  terminal_name: "The ProspectBoy 3000"
  terminal_subtitle: "Personal Salvage Assistant"
  local_node_name: "Local Node 07"
  palette: "amber16"
  hardware_effects: "subtle"

Example header:

THE PROSPECTBOY 3000 // LOCAL NODE 07
Personal Salvage Assistant
DAY 12/30   AP 5   SCRAP 184   SCORE 311

2.4 Internal Naming Note

“ProspectBoy 3000” is a creator-signature name connected to the project’s authorial identity. It should be treated as an original in-world product/device name.

Do not mention external inspirations in:

* UI text
* code comments
* class names
* CSS classes
* asset names
* marketing copy
* generated SVG metadata
* shipped documentation

⸻

3. What This UI Is Not

Avoid:

* typed-command gameplay
* fake shell prompts as primary input
* unreadable low-resolution text
* excessive flicker
* excessive CRT curvature
* heavy blur
* mandatory all-caps
* novelty UI that slows repeated play
* green Matrix-style hacker aesthetics
* overly faithful terminal emulation
* grimy realism that makes the game feel oppressive
* “look how retro I am” visual gimmicks

The retro device concept should appear through palette, typography, panel geometry, iconography, and sparse texture.

The UI should feel like a usable browser game first and a retro terminal second.

⸻

4. Visual Anchors

Primary inspirations:

* amber phosphor displays
* rectangular pixel and scanline feel
* BBS/ANSI iconography
* old personal digital assistants
* practical field devices
* salvage ledgers
* civic bulletin boards
* box-drawing UI panels
* old institutional software
* market boards
* post-collapse small business tools
* dry bureaucratic absurdity

The UI should look old enough to have personality but modern enough to be pleasant to use.

⸻

5. Hardware Presence

The hardware should be present, but subtle.

The player should gradually feel that the UI is running on old hardware. The game should not push this cleverness in the player’s face.

5.1 Use Sparingly

Allowed in moderation:

* faint scanline texture
* slight phosphor glow on active amber elements
* occasional screen-edge wear
* rare boot/status messages
* rare stuck-pixel artifacts
* soft panel burn-in effects
* very brief terminal settle animation after major page loads
* small device-status jokes

5.2 Avoid

Avoid:

* constant flicker
* strong glitch effects
* heavy screen distortion
* loud CRT simulation
* heavy vignette
* text blur
* readability loss
* animations on every click
* hardware effects that become the main visual event

5.3 Guiding Rule

The player should notice the old hardware after a few minutes, not have it shouted at them in the first three seconds.

⸻

6. Color System

The interface uses an amber-led 16-color palette.

This is a nod to early color displays and BBS/ANSI aesthetics. The palette may use more than amber, but amber remains dominant.

Other colors are functional accents, not decorative gradients.

6.1 Palette

Recommended CSS variables:

:root {
  --mm-black:        #050302;
  --mm-bg:           #090603;
  --mm-panel:        #130d06;
  --mm-panel-2:      #1d1409;
  --mm-amber-dim:    #8f6228;
  --mm-amber:        #ffb84a;
  --mm-amber-bright: #ffd37a;
  --mm-brown:        #3a2410;
  --mm-red:          #d45a3c;
  --mm-orange:       #e8843a;
  --mm-yellow:       #e6c15a;
  --mm-green:        #8aa35f;
  --mm-blue:         #5f8fa3;
  --mm-violet:       #9a7aa8;
  --mm-gray-dim:     #5f574a;
  --mm-gray:         #9b8f7a;
  --mm-white:        #f1dca5;
}

This is 16 colors total.

6.2 Color Philosophy

* Amber is the dominant identity color.
* Dark brown/black is the dominant background.
* Bright amber is reserved for active choices, urgent details, and key feedback.
* Dim amber is for metadata, borders, disabled states, and secondary terminal information.
* Accent colors should be rare and meaningful.
* Do not turn the UI into a rainbow dashboard.
* Do not use gradients for MVP unless explicitly approved.
* Do not rely on color alone to communicate important state.

6.3 Faction Color Use

Faction identity should be based primarily on shape language, not color.

Subtle color accents are allowed:

* Syndicate: orange/brown
* LibreMount: muted green
* Faculty: muted blue
* Purifiers: red/orange
* Revelationists: violet/yellow

Faction icons must still work as pure amber/currentColor glyphs.

⸻

7. Typography

Magic Mountain should be monospace-first.

Monospace supports:

* ledgers
* AP/scrap/score display
* artifact estimates
* inventory tables
* market readouts
* faction registries
* Crier bulletins
* terminal framing

7.1 Font Direction

The ideal font is:

* readable
* free/open or safely licensable
* technical but not sterile
* retro-compatible but not a novelty pixel font
* comfortable for dense UI

Good candidates:

* IBM Plex Mono
* JetBrains Mono
* Atkinson Hyperlegible Mono
* Source Code Pro
* system monospace fallback

Aptos Mono is a good taste reference: modern, readable, restrained. Confirm redistribution/webfont licensing before bundling it.

7.2 Recommended CSS Stack

body {
  font-family:
    "IBM Plex Mono",
    "JetBrains Mono",
    "Atkinson Hyperlegible Mono",
    ui-monospace,
    SFMono-Regular,
    Menlo,
    Consolas,
    monospace;
}

7.3 Avoid

Avoid:

* tiny pixel fonts for primary text
* distressed fonts
* fantasy fonts
* handwriting fonts
* all-caps body text
* unreadable novelty terminal fonts

⸻

8. Tone

The UI tone should be BBS/ANSI playful, not grimdark and not clownish.

The world can be absurd. The interface should behave like a professional tool trying to keep up.

8.1 Desired Voice

The UI voice should be:

* dry
* practical
* concrete
* slightly bureaucratic
* lightly funny
* salvage-business-oriented
* confident but sometimes wrong
* never morally preachy

8.2 Good UI Copy Examples

BUYER CONFIDENCE: MOSTLY INTACT
THERMAL GOODS: OVER-REPRESENTED
FACULTY CLASSIFICATION: RUDELY PENDING
SHED CONDITION: ACCEPTABLE, GIVEN CIRCUMSTANCES
ITEM CLASSIFIED AS USEFUL BY SOMEONE WITH LOW STANDARDS
MARKET APPETITE: NARROW BUT REAL

8.3 Avoid

Avoid:

LOL JUNK TIME!!!
EPIC SALE BRO!!!
THE MACHINE GOES BRRRR
YOU ARE THE CHOSEN ONE
THIS CURSED RELIC HUNGERS
GOOD FACTION / EVIL FACTION

The humor should emerge from situation, classification, bureaucracy, and salvage desperation.

⸻

9. Layout Language

The UI should be built from rectangular terminal-like panels.

Common elements:

* top status strip
* central activity panel
* Crier/public bulletin feed
* Shed inventory summary
* faction pulse panel
* leaderboard snapshot
* action button row
* market buyer card
* artifact inspection panel
* season recap report
* modal terminal cards

9.1 Main Dashboard Concept

┌────────────────────────────────────────────────────────────┐
│ THE PROSPECTBOY 3000 // LOCAL NODE 07                      │
│ DAY 12/30   AP 5   SCRAP 184   SCORE 311   SEASON ACTIVE   │
├────────────────────────────────────────────────────────────┤
│ LEFT: Crier / market bulletins                             │
│ CENTER: Current activity / Mountain / Market Visit          │
│ RIGHT: Shed summary / Faction pulse / Leaderboard snapshot  │
├────────────────────────────────────────────────────────────┤
│ [PROSPECT] [VISIT MARKET] [SHED] [FACTIONS] [CERTS]        │
└────────────────────────────────────────────────────────────┘

This is conceptual, not mandatory literal ASCII.

9.2 Panel Style

Panels should feel like terminal windows or device apps, but use modern spacing and readability.

CSS borders are preferred over excessive literal box-drawing characters.

Box-drawing characters may be used sparingly for flavor.

9.3 Responsive Layout

On desktop, the dashboard may show several panels at once.

On mobile, panels should collapse into app-like sections or tabs.

Do not force a narrow PalmPilot portrait layout. The ProspectBoy borrows some PDA metaphors, but the dominant visual direction is amber ANSI salvage console.

⸻

10. Interaction Philosophy

The game is clickable and legible.

Use terminal-style buttons, but keep them normal web controls.

Examples:

[ PROSPECT — 2 AP ]
[ VISIT MARKET — 1 AP ]
[ PUSH AGAIN ]
[ CASH OUT ]
[ OFFER ITEM ]
[ ACCEPT COUNTER ]
[ SEND AWAY ]
[ END DAY ]

Buttons should have:

* clear hover state
* clear active state
* clear disabled state
* keyboard focus state
* visible AP cost where relevant
* short, concrete labels

Do not hide important actions behind fake typed commands.

⸻

11. Navigation Metaphor

The ProspectBoy 3000 may borrow the organizational metaphor of a PDA: apps, ledgers, contacts, bulletins, and records.

Possible navigation labels:

[ FIELD ] [ SHED ] [ MARKET ] [ CONTACTS ] [ CRIER ] [ LEDGER ]

Or more direct gameplay labels:

[ PROSPECT ] [ SHED ] [ BAZAAR ] [ FACTIONS ] [ BULLETINS ] [ RECORDS ]

The second set is probably better for MVP clarity.

The UI should not lean heavily into a PalmPilot clone. PDA influence should inform the product metaphor, not constrain the screen shape or visual style.

⸻

12. Iconography: ANSI-Like Terminal Glyphs

Magic Mountain should use ANSI-like icons, but not literal text-only ASCII art.

Icons should feel like:

* terminal glyphs
* industrial stencils
* civic pictograms
* faction seals
* salvage registry symbols
* high-resolution pseudo-ANSI marks
* line-art SVG badges

12.1 Icon Rules

Icons should:

* use simple geometric forms
* be readable at 24x24 and 32x32
* work at 128x128 for faction pages
* use consistent stroke width
* use a shared square canvas
* preferably use viewBox="0 0 128 128"
* avoid tiny detail
* avoid gradients
* avoid realistic illustration
* avoid emoji style
* avoid painterly rendering
* avoid external assets
* work as one-color amber/currentColor

12.2 SVG Constraints

When generating SVG icons, use these constraints:

Create valid standalone SVG.
Use viewBox="0 0 128 128".
Use only inline SVG elements.
No external assets.
No embedded raster images.
No text elements.
No gradients unless explicitly requested.
Use 1–2 colors max.
Prefer currentColor.
Keep it readable at 24px.
Use simple paths, circles, rectangles, and polygons.
Group elements semantically.

⸻

13. Faction Visual Identity System

Faction identity must be strong.

Factions should be recognizable from icon shape alone. Color may support identity but must not carry it alone.

The five factions should share the same terminal-glyph design system but differ in silhouette, geometry, and symbolic vocabulary.

⸻

13.1 The Syndicate

Core idea:

Commercial resale, logistics, leverage, debt, inventory control, extraction.

Visual personality:

* efficient
* rectilinear
* modular
* transactional
* containerized
* grid-based

Shape language:

* stacked crates
* linked rectangles
* barcode marks
* ledger columns
* coin slot
* cargo hatch
* chain links
* inventory grid

Avoid:

* gangster clichés
* skulls
* guns
* luxury mafia styling

Icon should communicate:

We know how to move goods.

Possible emblem:

A stack of three offset cargo rectangles inside a square frame, crossed by a barcode-like ledger mark.

⸻

13.2 LibreMount

Core idea:

Public distribution, mutual aid, practical use, commons, anti-hoarding.

Visual personality:

* open
* outward-flowing
* practical
* communal
* field-utility

Shape language:

* open hands
* shelter roof
* radiating distribution lines
* water drop
* utility cross
* shared container
* outward arrows
* open circle

Avoid:

* sentimental charity imagery
* modern NGO slickness
* heroic savior symbolism

Icon should communicate:

Things should be used, not hoarded.

Possible emblem:

An open container beneath a simple roof or arc, with three outward distribution lines.

⸻

13.3 The Faculty

Core idea:

Study, classification, records, controlled knowledge, signal, custody.

Visual personality:

* precise
* archival
* clerical
* analytic
* slightly secretive
* cataloguing

Shape language:

* eye
* waveform
* antenna
* book/ledger
* concentric rings
* index tabs
* catalog stamp
* observation aperture

Avoid:

* wizard school imagery
* fantasy books
* goofy professor symbols

Icon should communicate:

We observe, classify, and keep.

Possible emblem:

A central observation aperture inside concentric catalog rings, with small index ticks.

⸻

13.4 The Purifiers

Core idea:

Safety, containment, destruction, quarantine, hazard control.

Visual personality:

* severe
* angular
* warning-like
* disciplinary
* controlled
* harsh

Shape language:

* warning triangle
* containment ring
* flame
* filter mask
* hazard stripe
* crossed tools
* blocked circle
* disposal mark

Avoid:

* heroic police badge
* generic villain mark
* gore
* cartoon evil imagery

Icon should communicate:

We remove the dangerous.

Possible emblem:

A warning triangle inside a broken containment ring, crossed by a hard diagonal disposal bar.

⸻

13.5 The Revelationists

Core idea:

Meaning, omen, transformation, pattern, ritual interpretation, sacred custody.

Visual personality:

* symbolic
* strange
* geometric
* intense
* patterned
* not literally magical

Shape language:

* starburst
* eye-in-box
* split diamond
* radiating spiral
* nested glyphs
* transformation arrows
* signal-as-omen pattern
* repeated marks

Avoid:

* fantasy magic symbols
* pentagrams
* occult clichés
* glowing wizard effects

Icon should communicate:

Everything means something.

Possible emblem:

A split diamond with a central eye-like aperture and radiating terminal ticks.

⸻

14. Artifact Visual Language

Artifacts do not need detailed illustrations in MVP.

Use terminal readouts, glyphs, and schematic marks.

Artifact presentation should include:

* name
* condition
* estimated value
* value range
* instability
* behavior tags
* decay trend
* age
* possible faction interest
* small glyph or category icon

Artifact icons can be generic category glyphs:

* thermal
* water
* signal
* storage
* power
* medical
* field
* force
* revelation
* transformation
* instability
* sanitation
* food processing

Artifact icons should look like technical classification symbols, not collectible-card art.

⸻

15. Mountain Prospecting Visual Language

Prospecting should feel like a field scan/intake workflow.

Possible panel:

┌─ MOUNTAIN INTAKE ───────────────────────────────┐
│ Artifact: Warm Box With Too Many Latches         │
│ Condition: STRAINED                              │
│ Estimated Value: 42–57 scrap                     │
│ Instability: ███████░░░                          │
│ Classification: THERMAL / STORAGE / SUSPECT      │
│                                                  │
│ [ PUSH AGAIN ]  [ CASH OUT ]  [ DISCARD ]        │
└──────────────────────────────────────────────────┘

The emotional center is push-your-luck. The UI must clearly show:

* current value
* risk state
* instability
* consequence of cashing out
* danger of pushing again
* whether a breakthrough/evolution occurred

⸻

16. Shed Visual Language

The Shed is a salvage ledger, not a beautiful inventory grid.

It should show:

* artifact name
* condition
* estimated value range
* decay state
* tags
* best-known faction fit
* age
* urgency

The Shed should support sorting/filtering.

Recommended sort modes:

* highest estimated value
* most urgent decay
* newest
* oldest
* best faction match
* unstable/risky
* tag/category

Visual tone:

ledger full of strange junk

Avoid:

* fantasy backpack UI
* polished e-commerce grid
* overly pretty item cards
* hiding important decay information

⸻

17. Market Visit Visual Language

Market Visit should feel like a buyer intake session through the ProspectBoy.

A buyer/customer card should show:

* faction icon
* buyer description
* visible tells/hints
* irritation/patience meter
* possible demand clues
* offered item
* offer amount
* counter-offer if applicable
* action buttons

Example:

┌─ BAZAAR BUYER ROUTED ───────────────────────────┐
│ FACTION: THE FACULTY          SIGNAL: PARTIAL    │
│ BUYER: Archivist with sealed gloves              │
│ TELL: Keeps asking whether it "records itself."  │
│ PATIENCE: ███░░                                  │
│                                                  │
│ Offer an artifact from Shed.                     │
└──────────────────────────────────────────────────┘

Customer irritation should be clear but not cartoonish.

17.1 Market Dynamics Visibility

Market dynamics must not feel like hidden punishment.

Use Crier messages, buyer comments, and terminal notices.

Examples:

THERMAL GOODS ARE COMMON THIS WEEK.
BUYERS ARE ASKING WHETHER YOURS IS DIFFERENT.
SIGNAL DEVICES ARE SCARCE.
FACULTY BUYERS ARE CIRCLING.
PURIFIER INTAKE TABLE ACTIVE:
UNSTABLE DEVICES ACCEPTED UNTIL FURTHER REGRET.

⸻

18. Crier Visual Language

The Crier is a public bulletin feed.

It converts system state into diegetic social feedback.

The Crier should look like:

* terminal bulletin board
* public exchange notice
* BBS feed
* municipal news ticker
* rumor ledger
* market notice board

Crier messages should:

* explain faction movement
* explain market dynamics
* hint at demand shifts
* reflect repeated player behavior
* foreshadow random events
* make the world feel reactive

Crier messages should not over-explain formulas.

Example:

CRIER // MARKET BULLETIN
Too many warm boxes crossed the Bazaar this week.
Syndicate buyers now ask whether yours is "one of the early ones."

⸻

19. Faction Screen Visual Language

Faction screens should feel like registry/contact records.

Each faction card/page should show:

* faction icon
* standing
* influence
* artifact intake profile
* recent sales
* known interests
* current market appetite
* recent Crier-linked activity

Avoid presenting factions as moral alignments.

Do not label factions good/bad.

Show appetite, behavior, relationship, and consequence.

⸻

20. Skills and Records Visual Language

Skills should feel like training/certification records inside the ProspectBoy.

Examples:

TRAINING RECORD
Prospecting II: Improved scan discipline
Upcycling I: Fewer catastrophic guesses
Selling III: Better tells, fewer insulting offers

Records should feel like seasonal ledgers.

Season recap should feel like an archived business report plus social consequence summary.

⸻

21. Accessibility and Usability

The visual style must not harm usability.

Requirements:

* sufficient contrast
* no essential information conveyed by color alone
* scanlines/effects must not obscure text
* buttons must have focus states
* icons need labels/tooltips
* tables/lists must be readable
* animations should be brief
* reduced-motion preference should be respected
* mobile layout must not require tiny click targets
* body text must not be too small
* all repeated gameplay actions must remain fast

Retro style is never an excuse for bad UI.

⸻

22. Implementation Guidance

Start with reusable CSS variables and components.

Suggested components:

* TerminalFrame
* DeviceHeader
* StatusStrip
* TerminalPanel
* ActionButton
* CrierFeed
* FactionBadge
* ArtifactLedgerRow
* MarketBuyerCard
* ConditionMeter
* InstabilityMeter
* TerminalNotice
* SeasonReport

Do not hardcode style into every screen.

Build a small design system first.

⸻

23. First UI Implementation Target

Do not redesign the whole game at once.

Create one vertical UI slice:

* top ProspectBoy header/status strip
* Mountain prospecting panel
* Shed summary
* Market Visit buyer card
* Crier feed
* five faction badges

Success criteria:

* It feels like Magic Mountain immediately.
* It is readable.
* Buttons are obvious.
* Faction icons are recognizable at small size.
* The terminal/PDA frame explains the game rather than obscuring it.
* The UI looks intentional, not like placeholder programmer HTML.
* The UI does not feel grimdark.
* The UI does not feel clownish.

⸻

24. Prompt for Generating Faction SVGs

Use this prompt or adapt it:

Create a cohesive set of five SVG faction icons for the browser game Magic Mountain.
Visual style:
- amber-led 16-color terminal palette
- pseudo-ANSI / industrial stencil / civic terminal pictogram
- high-resolution modern SVG, visually inspired by old amber CRT/BBS interfaces
- playful but not silly
- one-color icons using currentColor must work
- optional subtle secondary accent color
- no gradients
- no text
- no raster images
- no external assets
- readable at 24px and 32px
- viewBox="0 0 128 128"
- consistent stroke width and visual density across all five icons
- use simple geometric shapes, paths, circles, rectangles, and polygons
- icons should work as faction badges in a salvage-console UI
Factions:
1. The Syndicate
Commercial resale, logistics, leverage, inventory control.
Shape language: crates, ledgers, barcode marks, linked rectangles.
Avoid gangster clichés.
2. LibreMount
Public distribution, mutual aid, practical use, commons.
Shape language: open container, shelter, outward distribution lines, utility marks.
Avoid sentimental charity imagery.
3. The Faculty
Study, classification, records, controlled knowledge, signal.
Shape language: aperture, eye, waveform, catalog rings, index ticks.
Avoid wizard-school imagery.
4. The Purifiers
Safety, containment, destruction, quarantine, hazard control.
Shape language: warning triangle, containment ring, disposal bar, hazard stripe.
Avoid gore or villain imagery.
5. The Revelationists
Meaning, omen, transformation, pattern, ritual interpretation.
Shape language: split diamond, eye-like aperture, radiating ticks, nested glyphs.
Avoid fantasy magic or occult clichés.
Return valid SVG for each icon separately.

⸻

25. Final Design Principle

The visual design should make the game feel like:

A weird salvage economy running through a warm amber personal business device that still works because nobody has invented anything more trustworthy.

The ProspectBoy 3000 should frame the experience, not imprison it.

The UI should help players understand risk, inventory, market timing, faction pressure, and seasonal progress.

The game should feel playful, readable, strange, and economically alive.

