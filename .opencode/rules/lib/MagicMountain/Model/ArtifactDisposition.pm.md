# Model::ArtifactDisposition — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Disposition records are
> write-once sale archives. They must NEVER be mutated after creation.

## Additional Constraints
- NEVER modify a disposition record after creation. They are permanent
  archives of completed sales.
- NEVER access character, season, or faction data from this model.
