# Maintenance.pm — Module Boundary Rules

> Owns the daily maintenance window state machine: timer entry point,
> `bot_window_open` flag, `_rollover` routine. Does NOT implement game rules,
> bot execution, or day-rollover logic.

## Responsibilities
- Timer entry: `dailyMaintenance()` called by the 60-second recurring timer
- Window state machine: `bot_window_open` flag, `in_maintenance` flag
- `_rollover` routine: coordinates backup → `in_maintenance(1)` → `on_maintenance` → `in_maintenance(0)` → `bot_window_open = 0`
- Exactly-once guard: rollover fires once (subprocess callback OR deadline), winner cancels the other
- Clock abstraction: `clock` attribute for testability
- `compute_next_maintenance_window`, `recent_maintenance_boundary`
- `catch_up` method for missed-cycle recovery

## Constraints (MUST NOT)
- NEVER implement day-rollover logic (belongs in `Service::DailyMaintenance::run_day`)
- NEVER spawn processes or manage subprocess state directly (belongs in `Service::DailyMaintenance::open_bot_window`)
- NEVER access `$self->{row}` directly — use `getCol`/`setCol`
- NEVER call `url_for` or construct URLs

## Signs of a Violation
- Any `$self->{row}` access outside getter/setter methods
- `on_maintenance` callback implementation in this module
- Direct HTTP requests or subprocess spawning in this module
- Game math, artifact logic, or character state mutation
