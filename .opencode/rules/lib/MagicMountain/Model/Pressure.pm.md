# Model::Pressure — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Pressure records track
> PvP rival actions between characters.

## Additional Constraints
- NEVER access account, season, or faction data from this model.
- Age-based filtering (`max_age_days`) is a data query parameter,
  not game logic — the caller provides the threshold.
