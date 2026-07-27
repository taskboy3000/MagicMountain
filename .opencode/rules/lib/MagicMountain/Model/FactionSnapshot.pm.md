# Model::FactionSnapshot — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Faction snapshots are
> write-once archives created during maintenance and season finalization.

## Additional Constraints
- NEVER modify a snapshot after creation.
- NEVER access character or season data from this model.
