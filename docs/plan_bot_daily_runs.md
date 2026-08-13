# Plan: Fix bots never acting during daily maintenance

## 1. RCA summary (background)

**Symptom:** After ~19 days, 3 of 4 live bots (Yvaine Flicker, Orlan Carapace, Ophira
Cinderborn) have score 0; Kael Stillwater has 36 from a single day-1 run.

**Evidence:**
- Bot state: AP 20/20, scrap 0, no pending activity, no skills (Kael: 36 scrap, stuck mid-activity).
- Transcript: every bot's only gameplay is `07-28 14:59` (day 1). Nothing in the 18 subsequent
  days despite daily maintenance at 00:02.
- Audit: bots log in every day at 00:02–03 but never logout — the run dies immediately after login.
- Day-1 bots *did* play, because that run came from `advance-day` (`on_maintenance` called
  directly, `in_maintenance` never set), and the historical server was multi-worker so other
  workers served the bot requests.

**Root cause (reproduced):** `DailyMaintenance::_run_bots` makes *blocking HTTP requests to the
app itself* (`http://localhost:$port`) from inside the maintenance timer callback. In a
single-process daemon (current deployment: `perl script/mountain daemon -l http://localhost:9000`)
the event loop is blocked in the callback, so it cannot serve those requests. Every bot request
hangs ~40s (UA inactivity timeout) then dies with `Login failed for X`, swallowed by the `eval`.
Compounding: even if served, the `no_maintenance` bridge 503s all routes while `in_maintenance=1`.

Repro (`/tmp/opencode/maint_repro3.pl`, real daemon + current code): `Bot bot-fixed_highest-001
daily run failed: Login failed` ~40s after maintenance start; maintenance then completes. Fails
even via the `advance-day` path (`in_maintenance=0`). `simulate.pm` works because it uses
in-process dispatch; `t/bot_maintenance.t` misses the bug because it calls `on_maintenance`
directly (never the production `dailyMaintenance`, no `in_maintenance=1`).

**Why the fix is a new command, not a repair of the sync path:** the root cause is the
fundamental constraint that a single-process server cannot serve blocking HTTP requests made from
inside its own event-loop callback. Any sync fix keeps that constraint. The chosen design moves
bots to an external process (see §2), which also gives a manually-runnable bot tool for debugging
and one single bot-execution path.

## 2. Design overview

New `MagicMountain::Command::bot_turn` (`perl -Ilib script/mountain bot-turn [bot-id]`): loads
config, finds the active season and its bot characters, and for each bot runs
`Agent->login($name)` → `Routine->new(agent => ..., profile_id => ...)->run_day` over HTTP to
the daemon (`X-Bot-Service-Token` on every request). An optional **bot-id argument** (character
id) runs that one bot only — for targeted debugging — while a bare invocation runs every bot in
the active season. Logs per-bot failures; exits non-zero if any bot failed. Manually runnable at
any time for debugging; this is the **only** production path by which bots take a turn
(maintenance and `advance-day` spawn this same command).

Command details:
- **Bot selection**: optional `bot-id` argument (character id, `getopt` convention matching
  `advance_day`) → run that one bot; no argument → all bot characters in the active season
  (seeded+shuffled). Unknown/unfound id → warn and exit non-zero.
- **Base URL**: derived from the daemon's actual listen socket, not `config->{port} // 9000`
  (the daemon binds via `-l`; a wrong port would silently reproduce the "bots never act" bug).
  The daemon passes its listen URL to the subprocess via env (`MOUNTAIN_DAEMON_URL`); the
  command uses it or falls back to config. This is the last hardcoded URL removed from the
  service layer.
  - **Plumbing owner**: `script/mountain` parses `-l` before `start_app` and sets
    `MOUNTAIN_DAEMON_URL` in the daemon process env (alternatively a `before_command` plugin
    hook stashes it into config for `open_bot_window` to read). Normalize: `-l http://*:9000`
    → `http://localhost:9000` for the child; `http+unix://` gets a documented fallback (child
    connects via config host/port). Add `script/mountain` to §7 and test the env propagation.
- **Turn order**: preserve current determinism by porting the existing seed derivation from
  `DailyMaintenance::_run_bots` into `bot_turn` — season IDs are UUID strings, so `srand(
  season_id + day)` numeric-converts to `srand(day)` plus a warnings noise. Use the current
  string-hash seed (`unpack('C*', $id)`-style) + day, then shuffle the bot list, so per-day
  turn order (and test outcomes) is reproducible.
- **Routine construction**: mirror today's correct call —
  `Routine->new(agent => ..., profile_id => $char->getCol('bot_profile_id'))->run_day`.
  `Routine->run_day($profile_id)` treats its arg as a hashref and dies at runtime.
- **Boot guard**: the command is a `Mojolicious::Command`, so `startup` runs
  `catch_up_missed_cycles`/`ensureActiveSeason` on boot. Spawned mid-window that would roll the
  day a second time, so the daemon spawns with `MM_SKIP_CATCHUP=1` and `startup` skips both when
  that env is set (manual runs keep default behavior). Manual runs mid-window are a footgun —
  document `MM_SKIP_CATCHUP=1 perl -Ilib script/mountain bot-turn` in the command's usage text
  and in GAME_MECHANICS.md.

Daily maintenance becomes a **window** instead of a synchronous block:

```
end_of_day_hour            last bot exits            done
    │      bots play day N (external process)        │
    ▼            ~2-3 min                            ▼
 window opens  ──────────────────────────────→  rollover (brief, locked)
 (token gate on logins)                      (in_maintenance=1)
```

- The window opens at the configured `end_of_day_hour` (existing key).
- While open, the game day is **held open** (does NOT roll). Bots play day N.
- When the last bot finishes (`bot-turn` subprocess exits), the rollover runs and the window
  closes. This preserves the rule: *the game day does not finish until the bots have taken a
  turn.*
- Nominal bot runtime is ~1 minute (day-1 evidence: 4 bots, full cycles, ~2s). The window is
  expected to be minutes long.

## 3. Window lifecycle (daemon-side orchestration)

Ownership: `Maintenance::dailyMaintenance` stays the timer entry point and owns the window
state machine (`bot_window_open`, `next_run` advance, backup step, exactly-once rollover via
the existing `on_maintenance` hook). `Service::DailyMaintenance` owns the bot-window
*operations*: `open_bot_window` (set `bot_window_open`, advance `next_run`, spawn the
subprocess, schedule the deadline) and the rollover body. The 60s recurring timer continues to
call `dailyMaintenance` only. New flag `bot_window_open` on `MagicMountain::Maintenance`
(separate from `in_maintenance`), readable by the login gate (§4) via an `is_bot_window`
helper.

1. **Window opens** — `dailyMaintenance` sees maintenance due and calls `open_bot_window`:
   - re-entry guard: `return if $self->bot_window_open`,
   - set `bot_window_open = 1`, advance `next_run` (prevents re-entry),
   - spawn the `bot-turn` subprocess **non-blocking** (`Mojo::IOLoop->subprocess`) — the loop
     stays free so bots' HTTP requests are served normally,
   - set `MM_SKIP_CATCHUP=1` + `MOUNTAIN_DAEMON_URL` **inside the child callback, after the
     fork** — env set around the `subprocess()` call is restored before the fork runs on the
     next loop tick and would silently no-op,
   - schedule the deadline timer (§5).
   - If no bot *characters* exist in the active season (mirror `_run_bots`' `return unless
     @$bot_chars` — `bots.count` alone can be nonzero with zero bot chars), skip the window
     entirely and roll over directly (no gate, no spawn).
2. **Bots play** — `in_maintenance` stays 0; bots' requests pass the normal route stack. The only
   restriction is the login token gate (§4).
3. **Window closes** — subprocess completion callback (the "last bot" signal; fires regardless
   of the child's exit code) re-enters `Maintenance` for the rollover via a single shared
   `_rollover` routine: `_backup_data` → `in_maintenance(1)` → `on_maintenance` (rollover only,
   see §6) → `in_maintenance(0)` → `bot_window_open = 0` (logins reopen).
   - Exactly-once guard: rollover runs once, whichever fires first (subprocess callback or
     deadline); the winner cancels the pending deadline timer (or the loser no-ops on
     `bot_window_open == 0`).
   - The subprocess parent callback must return only simple scalars (e.g. the exit code) — Mojo
     serializes return values across the pipe as JSON, and deserialize failures are silently
     swallowed.
4. **Restart/shutdown mid-window** — `bot_window_open` is in-memory only; on restart, startup
   `catch_up_missed_cycles` advances missed days without bots (unchanged behavior, documented).
   Note: the daemon's own `bot-turn` child must NOT trigger this — the `MM_SKIP_CATCHUP` guard
   (§2) prevents the subprocess from rolling the day on boot. Shutdown mid-window orphans the
   child (reparented to init, self-healing via the next daemon's catch-up); a restart while an
   old child still lives can race the new window's `bot-turn` on the same bot accounts — rare,
   harmless, documented. Optionally track the child pid and kill on shutdown.

## 4. Login token gate

While `bot_window_open` is true, the login path rejects any login **without a valid
`X-Bot-Service-Token`** (same trust boundary already used by `Sessions.pm` for bot logins).
Single enforcement point — `Sessions::_build_session`, the session-creation chokepoint reached
by both `create` (incl. its existing-session early return) and `recover`, so no route can
bypass the gate; no route bridge; `MagicMountain.pm` only exposes the state via an
`is_bot_window` helper. Credential-based, not IP-based, so it survives reverse-proxy
deployments where humans and bots share a source IP. Bots always send the token
(`Bot::Agent::_req`); humans don't. The gate responds **503 with a human message** (asserted
in tests). Decisions:
- **Login-only gate** — existing human sessions can still act during the window (the day hasn't
  rolled; harmless). Full lockout (gate all non-token routes) noted as an alternative.
- `in_maintenance`/`no_maintenance` 503 bridge is **unchanged** and still guards the brief
  rollover moment only.

## 5. Deadline valve (no halting problem)

The window must never stall the 30-day season. One-shot timer at window-open: if bots haven't
finished within `maintenance_bot_deadline_minutes`, run the same rollover (day advances; that
day's bots are skipped and logged).

- Default **10 minutes** (config key `maintenance_bot_deadline_minutes`, tunable per deployment;
  documented in `docs/TUNING.md`). Nominal runtime ~1 min → ~10x margin; worst realistic case
  (hung request bounded by UA inactivity timeout ~40s, command startup) is < 2 min.
- Read with defined-or-default (so `0` is honored, not silently replaced by the default). `0`
  means immediate deadline (rollover as soon as the window opens); tests use ~1s for a
  deterministic, non-racey timeout.
- The deadline does **not** kill a still-running `bot-turn`; if it logs in after the rollover it
  simply plays late on day N+1 — no gameplay harm.

## 6. Rollover semantics

- `run_day` loses the `_run_bots` call; it becomes rollover-only (clear modifiers, day++, AP
  reset, shed decay, market reset, climate, events, crier, faction snapshots, finalize check,
  `last_maintenance`). Runs under `in_maintenance(1)` via the existing `on_maintenance` hook,
  wrapped by the shared `_rollover` routine (§3).
- **`advance_day` shells out to `bot-turn` (user decision, 2026-08-13):** advancing the game day
  runs the bots — it's part of the day. `advance_day` spawns `bot-turn` (env `MM_SKIP_CATCHUP=1`
  + `MOUNTAIN_DAEMON_URL`, via the same argv/env builder used by the daemon's `open_bot_window`),
  waits for it to exit, then calls the synchronous `on_maintenance` (rollover). Bots' day-N
  activity is included in the rollover snapshot — same semantics as the window. If the daemon is
  unreachable, log the bot failures and still roll (graceful degradation); a hung child is
  operator-interruptible (Ctrl-C). No deadline valve needed here — this path is operator-attended.
- `catch_up` already never spawned bots and stays bot-free. It keeps calling the synchronous
  `on_maintenance` and does **not** gain the backup step (backup stays in the window-only
  `_rollover` routine, as today).

## 7. Files affected

| File | Change |
|------|--------|
| **NEW** `lib/MagicMountain/Command/bot_turn.pm` | The command: optional `bot-id` argument (run one bot) or all season bots; per-bot `Agent->login` + `Routine->new(...)->run_day` over HTTP with token; UUID-safe seed (ported from `_run_bots`) + shuffle for deterministic turn order; base URL from `MOUNTAIN_DAEMON_URL` env (fallback config); logs failures, non-zero exit on any bot failure |
| `lib/MagicMountain/Service/DailyMaintenance.pm` | Remove `_run_bots` from `run_day`; add `open_bot_window` (set `bot_window_open`, advance `next_run`, non-blocking subprocess spawn with `MM_SKIP_CATCHUP`/`MOUNTAIN_DAEMON_URL` env, deadline timer); rollover-only `run_day` |
| `lib/MagicMountain/Maintenance.pm` | Owns window state machine: `bot_window_open` flag; `dailyMaintenance` calls `open_bot_window` then, on subprocess-completion/deadline, runs exactly-once rollover via existing `on_maintenance` hook (backup step preserved) |
| `lib/MagicMountain.pm` | `startup` skips `catch_up_missed_cycles`/`ensureActiveSeason` when `MM_SKIP_CATCHUP` is set; `is_bot_window` helper; config default `maintenance_bot_deadline_minutes => 10`; recurring timer continues to call `dailyMaintenance` |
| `lib/MagicMountain/Controller/Sessions.pm` | Enforce the token gate in `_build_session` (chokepoint for both `create` and `recover`) while the window is open — non-token logins rejected, 503 + human message |
| `lib/MagicMountain/Command/advance_day.pm` | Shell out to `bot-turn` (shared argv/env builder: `MM_SKIP_CATCHUP=1` + `MOUNTAIN_DAEMON_URL`), wait for exit, then rollover via `on_maintenance`; graceful roll if daemon unreachable |
| `script/mountain` | Parse `-l` before `start_app`; set `MOUNTAIN_DAEMON_URL` in the daemon env (normalized `localhost` host; `http+unix://` documented fallback) |
| `magic_mountain.yml` | Add `maintenance_bot_deadline_minutes: 10` |
| `docs/GAME_MECHANICS.md` | §Daily Maintenance rewritten: window semantics, `bot-turn` command, token gate, deadline; fix stale `MagicMountain.pm:189-337` ref |
| `GAME_ARCHITECTURE.md` | Rewrite §3.2/§3.3 (maintenance lifecycle; "why not separate process" → daemon-coordinated subprocess worker), §8.1 step 1 (bots in external window, not `on_maintenance`), §14 (in-process `Service::BotRunner` → `Command::bot_turn`), §4 boundary-table "Bot" row (direct persistence → external command + token) |
| `docs/TUNING.md` | Document `maintenance_bot_deadline_minutes` |
| `.opencode/rules/` | New `Maintenance.pm.md` (owns window state machine; timer entry) + `Service/DailyMaintenance.pm.md` (owns `open_bot_window` + rollover body; supersedes generic `services.pm.md` for this module) — this also creates the `.opencode/rules/lib/MagicMountain/Service/` directory. Rule text: bots never run via in-process sync dispatch on *production* paths — explicit carve-out for `Command::simulate` (dev/test tool) |
| `AGENTS.md` | Quick Reference: `perl -Ilib script/mountain bot-turn [bot-id]`; Architecture Rules note: bots take turns via the external `bot-turn` command only |
| `t/maintenance.t` | `FakeApp` gains `config => { bots => { count => 0 } }` + `daily_maintenance` stub so the new `dailyMaintenance` → `open_bot_window` path doesn't die; existing rollover assertions still pass via the no-bots fast path |

No route, template, or controller-game-logic changes beyond the login gate in
`Sessions::_build_session`.
No `bin/walkthrough` change needed (the gate is window-conditional and unreachable from the
walkthrough's flow) — stated here to satisfy the endpoint-change convention.

**Atomicity:** the runtime changes (startup `MM_SKIP_CATCHUP` guard, `bot_window_open` flag,
`open_bot_window` + spawn + deadline, `_rollover` exactly-once, `_run_bots` removal, login
gate) must land as **one commit** — intermediate states are broken: window-without-guard lets
the child double-roll the day; `_run_bots`-removed-without-window stops bots entirely;
window-with-`_run_bots`-still-present re-runs bots synchronously inside the completion callback
(the exact deadlock this plan fixes). Docs/rules/TUNING/AGENTS updates follow in the same
change but do not gate the runtime flip.

## 8. Tests

- **NEW `t/bot_turn.t` (integration):** start the real app listening on a dynamically allocated
  **non-9000** port (`Mojo::Server::Daemon` on `127.0.0.1:0`, or bind-and-release an
  `IO::Socket::INET`), seed the data dir *before* the daemon boots, run `MOJO_MODE=test` (so the
  60s maintenance timer never fires mid-test), pass the listen URL as `MOUNTAIN_DAEMON_URL`, run
  `bot-turn` as a subprocess (fork+exec, `/health`-wait pattern from `bin/walkthrough`) → bots
  log in, prospect, log out; character AP/score/shed change; deterministic turn order
  (seed+shuffle); non-zero exit when a bot's turn fails. The child must also run with
  `MM_SKIP_CATCHUP=1` so its startup catch-up can't roll the day and flake the day/snapshot
  assertions. Also exercise the **single-bot form** (`bot-turn <bot-id>`): only that character's
  AP/score/shed change, others untouched; unknown id exits non-zero.
- **Boot guard:** spawn `bot-turn` with `MM_SKIP_CATCHUP=1` mid-window (past `end_of_day_hour`,
  day not yet rolled) → the subprocess performs no rollover on boot; day advances exactly once
  when the daemon's completion callback fires.
- **Exactly-once rollover guard:** on one window, fire completion-then-deadline and
  deadline-then-completion (separate windows) → exactly one rollover, one window close, pending
  deadline timer cancelled.
- **All-bots-failed completion:** rotate the bot token mid-window so every bot fails → the child
  exits non-zero, yet the completion callback still rolls the day over and closes the window.
- **Token gate (`t/bot_agent.t` or new):** with `bot_window_open=1`, a token-bearing login
  succeeds and a non-token login is rejected (**503**, asserted) — covering `create`'s
  existing-session early return and `recover`; with the window closed, non-token login succeeds.
- **Deadline config:** unit test that config `0` yields a zero-second deadline
  (defined-or-default read); integration deadline path at ~1s with slow/failing bots → rollover
  still runs within the deadline; day advances; window closes.
- **Window lifecycle (production caller, per lifecycle-entry-point rule):** open the window
  through `DailyMaintenance` orchestration against a real daemon socket (in-process tests cannot
  serve the forked child), set `MOUNTAIN_DAEMON_URL` before the window opens, pump the loop until
  the window closes (hard timeout), assert: day advanced *after* bots acted (snapshot includes
  bot activity), audit has bot `login`/`logout`, window closed, logins reopened.
- **`advance_day` + bots (integration):** against a running daemon, `advance-day` spawns
  `bot-turn`, bots act (activity in the rollover snapshot), then the day rolls; with the daemon
  down, the command logs bot failures and still rolls.
- **Keep** existing `t/bot_maintenance.t` subtests (default token, `advance-day` still ends with
  bots having acted) but rename the stale "bot runs during maintenance" subtest — bots no longer
  run inside `on_maintenance`; keep the `bot-turn`-independent routine/agent tests. Update
  `t/maintenance.t` `FakeApp` for the new `dailyMaintenance` path.
- Manual: re-run `/tmp/opencode/maint_repro3.pl` shape against the fix → bots play, no
  "Login failed" warn.
- Expect to re-baseline the test budget (`make test-budget-baseline`) — `t/bot_turn.t` and
  `t/maintenance.t` change the suite timing.

## 9. Verification / gates

`make indent && make clean` → targeted tests → `make ci-check` (tests + walkthrough + perlcritic +
test-budget) → `make cover && make report` (≥85%) → `make verify` → offer `@post-verify`.

## 10. Decisions captured / open items

- Token gate is credential-based (proxy-proof), not IP-based. Agreed.
- Rollover runs *after* bots finish; day N does not close until bots turn. Agreed.
- Late-arriving bot processes are not killed; they play day N+1 harmlessly. Agreed.
- Deadline default 10 min, config-driven; `0` = immediate, read defined-or-default. Agreed.
- Window state machine owned by `Maintenance`; bot-window operations (`open_bot_window`,
  rollover body) owned by `Service::DailyMaintenance`. Agreed.
- Subprocess boot guard: `MM_SKIP_CATCHUP=1` prevents the spawned `bot-turn` from rolling the
  day on startup. Agreed.
- Single token-gate point at `Sessions::_build_session` (both `create` and `recover`), 503 +
  human message; `MagicMountain.pm` exposes only `is_bot_window`. Agreed.
- Deterministic bot turn order preserved via the existing UUID-safe seed derivation ported from
  `_run_bots` into `bot_turn` (not `srand(season_id + day)`). Agreed.
- `Routine` constructed with `profile_id`; `run_day` called arg-less. Agreed.
- `MOUNTAIN_DAEMON_URL` plumbing owned by `script/mountain` (parse `-l`, normalize, env).
  Agreed.
- Subprocess env (`MM_SKIP_CATCHUP`, `MOUNTAIN_DAEMON_URL`) set inside the child callback
  (post-fork); parent callback returns simple scalars only. Agreed.
- Backup step moves into a shared window-only `_rollover` routine in `Maintenance`;
  `advance-day`/`catch_up` gain no backup. Agreed.
- Runtime changes land as one atomic commit; docs/rules/TUNING/AGENTS follow in the same change
  but don't gate the flip. Agreed.
- **User decision (2026-08-13):** login-only gate during the window — block new non-token
  logins; existing sessions keep acting. Confirmed.
- **User decision (2026-08-13):** `advance-day` shells out to `bot-turn` (shared argv/env
  builder), waits for exit, then rolls — advancing the day runs the bots as part of the day;
  graceful roll if the daemon is unreachable. `catch_up` stays bot-free. Agreed.
- **User decision (2026-08-13):** `bot-turn` accepts an optional bot-id argument to run a single
  bot; bare invocation runs all season bots. Agreed.
- `t/maintenance.t` `FakeApp` updated for the new path; test budget re-baselined. Agreed.
- "No in-process bots" rule scoped to production paths; `Command::simulate` carved out as a
  dev/test tool. Agreed.
- Base URL comes from the daemon's listen socket (`MOUNTAIN_DAEMON_URL`), not a guessed port.
  Agreed.
- `GAME_ARCHITECTURE.md` §3.2/§3.3, §8.1, §14, §4 updated in lockstep. Agreed.
- Housekeeping: this file now lives at `docs/plan_bot_daily_runs.md` (repo-root plan
  convention); delete it once the implementation is committed. Agreed.

All previously open items are resolved; no open decisions remain.

## 11. Rejected alternatives

- **Bots after rollover** — simple, but the day finishes before bots play; faction snapshots and
  crier history would lag bot activity by a day.
- **In-process dispatch (`$ua->server->app`, sync maintenance)** — smallest diff and also holds
  the day open, but creates two bot-execution paths (maintenance in-process vs `bot-turn` over
  HTTP), reintroducing the divergence risk this plan exists to eliminate.
