# Model::ShedItem — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Shed items track artifacts
> in a player's inventory.

## Additional Constraints
- NEVER access character, season, or faction data from this model.
- Decay computation belongs in `ShedManager`, not in the model.
