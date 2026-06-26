I would emphasize that this is not a lore feature. It’s a usability feature that happens to deepen the fiction. That framing will help keep the implementation restrained.

⸻

PB3K Registry Design Proposal

I would like to add a small in-universe reference system to the PB3K.

This is not intended to become a traditional game encyclopedia or a large lore database. We are deliberately avoiding a “Hitchhiker’s Guide” style reference manual.

The design goal is much smaller.

The registry exists to answer the player’s immediate question:

“What is this thing I’m looking at?”

without interrupting gameplay.

Design Principles

* The registry is part of the ProspectBoy 3000.
* Entries are presented as field-reference documents, not narrative lore.
* Entries should be concise (approximately 4–8 lines of information).
* Players should never be required to read the registry to understand gameplay.
* The registry should reinforce the fiction while remaining optional.

Initial Scope

Initially support entries for:

* Factions
* Artifact types/classes
* Artifact traits/tags
* PB3K terminology
* Other important game concepts as needed

Navigation

Registry entries should be discoverable naturally.

Examples:

* Clicking a faction short name opens the faction registry entry.
* Clicking an artifact type opens its registry entry.
* Other terminology throughout the UI can gradually become clickable as appropriate.

Players should discover the registry organically while exploring the interface.

Tone

Registry entries should read like internal PB3K documentation.

Each entry should communicate:

* what this thing is
* why the operator should care
* any important operational notes

The tone should remain dry, bureaucratic, and occasionally humorous.

Avoid long historical exposition.

Avoid large walls of text.

The player should be able to read an entry in under 15 seconds.

Data Driven

Registry entries should be stored as structured data (YAML or equivalent), not hardcoded into templates or controllers.

The rendering system should simply display registry data.

This allows new entries to be added without changing Perl code.

Architecture

Treat the registry as another PB3K application.

It should follow the existing architecture:

* controllers remain thin
* models/services retrieve registry entries
* templates simply render the supplied view model

Do not embed registry knowledge into templates or controllers.

⸻

I would add one more sentence at the very end because I think it captures the spirit of the feature:

The registry should make the world feel larger than the game, without requiring the player to study the world in order to enjoy the game.

To me, that’s exactly the balance you’ve been striking with the PB3K. It rewards curiosity, but it never demands homework.
