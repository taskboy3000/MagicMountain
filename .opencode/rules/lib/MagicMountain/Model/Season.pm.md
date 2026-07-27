# Model::Season — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Season manages the game
> calendar and faction state. It must NEVER contain per-player logic.

## Additional Constraints
- NEVER contain per-player character data or game logic. Season-ending
  logic (`finalize`) belongs in a service.
- NEVER contain game-design constants (AP costs, thresholds). Use
  `daily_modifier($key, $default)` for tunable values.
- NEVER access character, shed, or disposition models directly.
  Cross-model orchestration belongs in a service.

## Allowed Methods
- `daily_modifier($key, $default)` — reads from `daily_modifiers` hash
- `faction_climate()` — reads from `faction_climate` column
- Standard CRUD from Model base class

## Signs of a Violation
- A method iterates characters or shed items
- A method computes scores, rankings, or clearance values
- A method returns a game-design constant like `2` for AP cost
