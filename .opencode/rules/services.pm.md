# Service — Module Boundary Rules

> Services contain extracted business logic that doesn't belong in controllers,
> models, or activities. They are instantiated per-request by controllers.

## Responsibilities
- Encapsulate cross-model orchestration (e.g. account deletion, season finalization)
- Provide view-data assembly (e.g. character view helpers)
- Perform stateless computations that don't fit in a single model or activity

## Constraints (MUST NOT)
- NEVER build HTML, CSS classes, or UI button structures. Return plain data
  structures (hashrefs, arrayrefs). View rendering belongs in templates or
  controller action-building.
- NEVER hardcode URLs. Receive URLs as pre-computed strings passed from the
  controller. This keeps `url_for` usage in the controller layer where the
  reverse-proxy prefix override works.
- NEVER encode game rules (AP costs, scrap thresholds, day counts, etc.).
  Receive precomputed values from the controller. Game rules change; services
  should not need updates when a cost or threshold is tuned.
- NEVER access `$self->app` for game state that could be passed as a parameter.
  If a method needs the current day, season state, or faction data, add a
  parameter and have the caller pass it.

## Signs of a Violation
- A service method contains `if ($ap >= N)` or similar game-rule check
- A service method builds a hash with keys like `class`, `data-action-url`,
  `disabled`, or other HTML/CSS attribute names
- A service method calls `$self->app->url_for` or contains a literal `/path`
- A service method accesses `$self->app->seasons`, `$self->app->characters`,
  or other domain models to read state that the caller already has
