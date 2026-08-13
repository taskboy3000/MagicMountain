# Service/DailyMaintenance.pm — Module Boundary Rules

> Owns the day-rollover body (`run_day`) and bot-window operations
> (`open_bot_window`). Bots never run via in-process sync dispatch on
> *production* paths — explicit carve-out for `Command::simulate` (dev/test tool).

## Responsibilities
- `run_day`: rollover-only day-advancement logic (clear modifiers, day++, AP reset, shed decay, market reset, climate, events, crier, faction snapshots, season-finalize check)
- `open_bot_window`: set `bot_window_open`, advance `next_run`, non-blocking subprocess spawn, deadline timer
- `catch_up_missed_cycles`: missed-cycle recovery (no bot runs)
- Backup step is in `Maintenance::_rollover` (shared window-only routine)

## Constraints (MUST NOT)
- NEVER make blocking HTTP requests from inside the event loop (causes deadlock in single-process daemons)
- NEVER call `_run_bots` or equivalent in-process bot dispatch on production paths
- `Command::simulate` is explicitly carved out as a dev/test tool that may use in-process dispatch
- NEVER access `$self->{row}` directly — use `getCol`/`setCol`
- NEVER construct URLs or call `url_for` (URL construction belongs in controllers)
- Game rules, artifact math, and character state mutation belong in Activity/Model classes

## Signs of a Violation
- `$ua->start` or `Mojo::UserAgent` blocking calls inside timer callbacks or synchronous maintenance paths
- `_run_bots` method or equivalent in-process bot loop
- Direct model mutation that bypasses Activity dispatch (except in `run_day` rollover body)
- URL construction in this module
