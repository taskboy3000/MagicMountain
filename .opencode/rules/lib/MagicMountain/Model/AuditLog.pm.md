# Model::AuditLog — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Audit log is append-only.

## Additional Constraints
- NEVER delete or modify existing log entries.
- NEVER read log entries for game-state decisions.
