# Model::BrokersCache — Module Boundary Rules

> See `Model.pm.md` for base-class rules. BrokersCache manages
> available broker offers for the black market.

## Additional Constraints
- NEVER access character, season, or faction data from this model.
- The `draw_random` method is a data query, not game logic.
