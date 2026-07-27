# Model::Session — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Session manages player
> login sessions with expiry.

## Additional Constraints
- NEVER reference characters, seasons, activities, or factions.
- Session expiry is a data query (`is_expired`), not game logic.
