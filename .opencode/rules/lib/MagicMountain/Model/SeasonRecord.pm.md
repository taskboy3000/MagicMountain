# Model::SeasonRecord — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Season records are
> write-once archives created during season finalization.

## Additional Constraints
- NEVER modify a season record after creation.
- NEVER access character, season, or faction data from this model.
