# Model::Transcript — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Transcript is an append-only
> event log. It must NEVER be read for game-state decisions.

## Additional Constraints
- NEVER delete or modify existing log entries.
- NEVER read transcript events for game-state decisions. Transcript
  is for reporting and debugging only.
