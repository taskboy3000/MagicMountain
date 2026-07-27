# Model::Character — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Character is a data model
> with invariants. It must NEVER contain game logic or view assembly.

## Additional Constraints
- NEVER contain game-math methods (`can_continue`, cost checks,
  eligibility checks). These belong in a service.
- NEVER access other models or activities (`$self->app->prospecting`,
  `$self->app->market`, `$self->app->shed`). Cross-model queries
  belong in a service.
- NEVER construct view data or display structures. Return raw column
  values only.
- NEVER encode game constants (AP costs, scrap thresholds, etc.).

## Allowed Methods
- `add_scrap($n)` — simple arithmetic, no game logic
- `add_score($n)` — simple arithmetic, no game logic
- `validate($col, $val)` — data invariants only (score never decreases,
  scrap non-negative, AP within max, skill range 0-4)
- `validate_save()` — data invariants only

## Signs of a Violation
- A method calls `$self->app-><something>` to access another model
- A method returns a hash with display keys (`label`, `icon`, `class`)
- A method checks `$ap >= N` or similar game-rule condition
