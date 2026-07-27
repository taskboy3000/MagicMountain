# Model.pm — Module Boundary Rules

> The base class for all persisted objects. Models are thin data-access
> objects. They must NEVER contain game logic, view assembly, or
> cross-model orchestration.

## Responsibilities
- Declare columns via `has columns => sub { ... }`
- Provide CRUD: `create`, `get`, `find`, `all`, `delete`, `save`
- Enforce data invariants via `validate()` and `validate_save()`
- Provide convenience accessors using `getCol`/`setCol`

## Constraints (MUST NOT)
- NEVER contain game math, artifact logic, or game-design constants
  (AP costs, value multipliers, thresholds, etc.). These belong in
  activities or configuration.
- NEVER access other models or activities (`$self->app->characters`,
  `$self->app->prospecting`, etc.). Cross-model orchestration belongs
  in a service.
- NEVER construct view data or assemble display structures. View
  assembly belongs in a service or controller.
- NEVER encode game rules (`can_continue`, eligibility checks, cost
  calculations). These belong in a service.
- NEVER call `->save()` on any object other than `$self`. Persistence
  of other objects is cross-model orchestration.

## Allowed Methods
- Column accessors: thin wrappers around `getCol`/`setCol`
- Query helpers: `find_by_username`, `find_by_player_id` — pure data
  lookups that return model instances
- Invariant checks: `validate()` and `validate_save()` — data integrity
  only, never game logic

## Signs of a Violation
- A model method calls `$self->app-><something>` to access another model
- A model method returns a hashref with display-oriented keys
  (`label`, `icon`, `action_url`)
- A model method contains `if ($ap >= 2)` or similar game-rule check
- A model method iterates records from a different model
