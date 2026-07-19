# Plan: Unified Bot Agent

Replace three separate mechanisms (BotRunner in-process API calls,
walkthrough hardcoded HTTP paths, NPC display-only badging) with one
HTTP client that discovers actions from the same JSON endpoints the
frontend uses.

## Architecture

```
                   Game Server (Mojolicious)
                  /    |    |    |    \
                 /     |    |    |     \
            JSON  JSON  JSON  JSON  JSON
               \   /      |      \   /
                Bot::Agent (HTTP client)
                     |
              Bot::Routine (orchestrator)
                     |
                Policy modules
            (Push, Sell, Skill, BM, PvP)
                     |
              Three consumption modes:
         simulation  |  live NPC  |  walkthrough
```

### Layer 1 — `MagicMountain::Bot::Agent`

A `Mojo::UserAgent` wrapper. Pure HTTP: no game logic, no policy, no
orchestration. Called by the routine layer.

```
has base_url    => 'http://127.0.0.1:9000'
has ua          => Mojo::UserAgent (or in-process via server attribute)
has csrf_token  => undef
has svc_token   => undef   # X-Bot-Service-Token for bypassing login blocks

sub login($name)       # POST /sessions → stores csrf_token
sub logout($self)      # DELETE /sessions

sub req($method, $path, $body?)  # all actions funnel through this
  - adds X-CSRF-Token header
  - adds X-Bot-Service-Token if svc_token is set
  - decodes JSON response
  - checks ok flag
  - returns decoded hashref

# Read endpoints (thin aliases to req)
sub nav        -> GET /nav
sub game       -> GET /game
sub prospect   -> GET /prospecting
sub market     -> GET /market
sub shed       -> GET /shed
sub skills     -> GET /skills
sub rivals     -> GET /pvp
sub factions   -> GET /factions
sub result     -> GET /result
sub black_mkt  -> GET /black_market

# Write endpoints (thin aliases to req)
sub begin_prospect            -> POST /prospecting/begin
sub push                      -> POST /prospecting/push
sub stop                      -> POST /prospecting/stop
sub resolve_event($choice_id) -> POST /prospecting/resolve_event
sub continue                  -> POST /result/continue
sub begin_market              -> POST /market/begin
sub offer($shed_item_id)      -> POST /market/offer
sub send_away                 -> POST /market/send_away
sub accept_counter            -> POST /market/accept_counter
sub accept_bm                 -> POST /black_market/accept
sub withdraw_bm               -> POST /black_market/withdraw
sub purchase_skill($skill_id) -> POST /skills/purchase
sub apply_pressure(%params)   -> POST /pvp/apply
```

Agent hardcodes HTTP paths because it is an HTTP client. These MUST
match the route definitions in `MagicMountain::buildRoutes`. When
renaming/adding a route, update both the route name and the Agent.

**X-Bot-Service-Token**: A random token from config (`bot_service_token`)
that the Agent sends on login. The Sessions controller checks this header:
if it matches, the bot-account block is skipped AND rate limiting is
skipped for that request. This is explicit, auditable, and not
bypassable from external IPs.

### Layer 2 — `MagicMountain::Bot::Routine`

The game-loop orchestrator. Knows the phase order (prospect → market →
skills → pvp) and owns the loop logic. Calls Agent to discover state
and perform actions, calls policies to make decisions.

```
has agent           => required
has profile_file    => 'content/bots.yml'
has profile_id      => undef
has transcript_cb   => undef   # optional callback for event logging

sub run_day($profile?)
  - load_profile if not passed
  - agent->login
  - _prospect_phase
  - _market_phase    (or _black_market_phase)
  - _skill_phase
  - _pvp_phase
  - agent->logout
  - return { ok => 1, actions => $count }

sub _prospect_phase
  - loop while AP >= 2 (from agent->game or action responses):
    - agent->begin_prospect
    - if event (choice): auto-pick first, agent->resolve_event, agent->continue
    - if event (passive): agent->continue, next
    - push loop:
      - agent->push  (response includes artifact with push_count, stage, value)
      - if collapse/breakthrough: done
      - if push: PushPolicy::evaluate($response, $profile->{push_policy})
        -> stop if yes: agent->stop

sub _market_phase
  - loop while AP >= 1 (check agent->game or action responses):
    - agent->begin_market
    - if hoarder policy: skip
    - if event: skip
    - SellPolicy::accept_customer -> send_away if no
    - offer loop:
      - agent->offer($shed_item_id)
      - switch on result:
        sold/sold_more: done or offer more
        counter_offer: SellPolicy -> accept_counter or next
        over_budget/no_match: next
        customer_left: done
      - check irritation/pressure vs policy limits

sub _black_market_phase
  - The market/begin handler internally routes to BM if MarketGate
    detects all items banned. The response from begin_market will
    indicate the redirect. Agent then calls black_mkt (GET) to see
    the deal, then accept_bm or withdraw_bm.

sub _skill_phase
  - agent->game (for player.scrap and player.skills)
  - agent->skills (for skill definitions with costs)
  - SkillPolicy::decide($composite_state, $policy_params)
  - agent->purchase_skill if decision

sub _pvp_phase
  - agent->rivals (GET /pvp)
  - agent->game (for player.faction_sales, player.score)
  - Assemble enriched context from multiple API calls
  - PressurePolicy::decide($enriched_context)
  - agent->apply_pressure if decision
```

#### Data assembly for policy calls

**PushPolicy** gets the push response directly — includes artifact
fields (stage, value, push_count) plus player snapshot.

**SellPolicy** gets market response + shed items. Routine calls
`agent->shed` and `agent->market` to build composite state.

**SkillPolicy** needs scrap (from `agent->game`), skill definitions
(from `agent->skills`), and current skill levels (from `agent->game`).
Routine assembles these into a composite state before calling decide.

**BlackMarketPolicy** gets the GET /black_market response which
includes premium_mult from the activity.

**PressurePolicy** needs rivals data + the bot's own faction_sales,
score, scrap, profile pvp_aggressiveness, and config values. Routine
assembles these from multiple agent calls and passes as context.

### Layer 3 — Policy Modules (adapt, not rewrite)

Existing modules stay. Their data source changes from internal model
objects to the JSON-decoded hashes the Agent returns.

**PushPolicy** — receives the push response hash (artifact + player).
Handlers today: `$art->{push_count}` → `$push_resp->{artifact}->{push_count}`.

**SellPolicy** — receives composite state with market_visit + shed items.
Handlers today: `$cust->{faction_id}` → `$state->{market_visit}->{faction}`,
`$item->getCol('decayed_value')` → `$state->{shed}[i]->{decayed_value}`.

**SkillPolicy** — receives composite state with player + skills.
Handlers today: `$char->getCol('skill_prospecting')` → lookup in
`$state->{skills}` array for `current_level`. `$char->getCol('scrap')`
→ `$state->{player}->{scrap}`.

**BlackMarketPolicy** — receives the BM show response with premium_mult.
Policy unchanged; premium comes from GET /black_market JSON response
instead of being computed inline.

**PressurePolicy** — receives enriched context from multiple agent
calls. Rather than accessing `$context->{app}->config->{pvp_cost_*}`,
the Routine passes config values and player state explicitly.

### Required Controller/Model Changes

These are changes to existing code that MUST happen before the Agent
and Routine can work correctly:

#### 1. Add `push_count` to prospecting push response

File: `lib/MagicMountain/Activity/Prospecting.pm`, line 183-190
(`_artifact_view`). Add `push_count => $artifact->{push_count}` to
the returned hash. This is the response the bot receives on every
push call — needed by PushPolicy to decide when to stop.

#### 2. Add `decayed_value` to shed JSON output

File: `lib/MagicMountain/Controller/Shed.pm`, line 60-73
(`_item_view`). Add `decayed_value => $item->getCol('decayed_value')`
to the returned hash. Currently the shed JSON has
`estimated_value_min` (~80% of decayed_value) but not the actual
`decayed_value`. SellPolicy needs the real value for threshold
comparisons.

Note: this contradicts the plan's earlier statement "no controller
changes needed for the JSON interface." These two additions are
necessary and minimal — each is a one-line addition to an existing
data structure.

#### 3. Bot login bypass via service token

File: `lib/MagicMountain/Controller/Sessions.pm`, lines 191-205.
Replace the IP-based bot block with a configurable `bot_service_token`
check. If the request carries `X-Bot-Service-Token` header matching
`$self->app->config->{bot_service_token}`, skip the bot-account block
and rate limiting for that request.

New config key: `bot_service_token` — a random string generated per
deployment. The Agent uses this as `svc_token`.

The Agent is configured with this token. For simulation/test modes,
the test server generates a random token and passes it to the Agent
via the same config.

#### 4. No new `Service::BlackMarket` needed

The premium multiplier formula already lives in
`Activity::BlackMarket::_premium_multiplier`. BotRunner.pm had a
duplicate copy. The duplicate gets deleted with BotRunner; no new
service is created. The Agent reads `premium_mult` from the
`GET /black_market` JSON response.

#### 5. Ensure `player` snapshot in action responses includes `faction_sales`

File: `lib/MagicMountain/Activity/Prospecting.pm`, line 175-181
(`_player_snapshot`). Currently returns action_points, scrap, score
but NOT faction_sales or skills. PressurePolicy needs faction_sales.

Either extend `_player_snapshot` to include `faction_sales` and
`skills`, or the Routine gets those from `agent->game` separately.
The latter is simpler — no model changes, just an extra API call.

### Consumption Modes

#### Mode A: Simulation (`script/mountain simulate`)

Use Mojo's in-process `server` attribute
(`Mojo::UserAgent->new(server => $app)`) — full Mojo dispatch
without TCP overhead.

Create one Agent per bot, log in with svc_token, call
Routine->run_day across all days. Log transcript events via
transcript_cb.

#### Mode B: Live NPC (maintenance callback)

The maintenance callback in `MagicMountain.pm` (line 219 currently
calls `$app->bot_runner->run_day($bot_char)`). Replace with:

```perl
my $ua = Mojo::UserAgent->new(server => $app);
my $agent = Agent->new(
    base_url  => "http://127.0.0.1:${port}",
    ua        => $ua,
    svc_token => $app->config->{bot_service_token},
);
my $routine = Routine->new(
    agent      => $agent,
    profile_id => $bot_char->getCol('bot_profile_id'),
    transcript_cb => sub { $transcript->log_event($_[0]) },
);
$routine->run_day;
```

Session management for N bots each day:
- Each `run_day` call logs in, runs all phases, logs out.

#### Mode C: Walkthrough (`bin/walkthrough`)

The walkthrough script becomes a specific profile + Routine
configuration that navigates the game and asserts each response.
Uses Agent->req for every request. Assertions check JSON response
fields.

This is a full re-implementation of bin/walkthrough — the existing
script is 468 lines of DOM scraping and hardcoded paths that all
get replaced. The new walkthrough uses Agent + Routine and asserts
JSON field values.

### What Gets Removed

- `lib/MagicMountain/Service/BotRunner.pm` — entire file (430 lines)
- Hardcoded paths in `bin/walkthrough` — replaced by Agent calls
- Bot login block in `Controller/Sessions.pm:194-205` — replaced
  with service token mechanism
- Premium formula duplicate at BotRunner.pm:146 — the canonical
  copy stays in `Activity::BlackMarket::_premium_multiplier`

### What Stays

- Policy modules — adapted data source but same interface
- Bot profile definitions (`content/bots.yml`)
- Bot account/character model columns (`is_bot`, `bot_profile_id`)
- Simulation infrastructure (`bin/run_sims`, `bin/analyze`) — just
  consumes different output format
- `bin/analyze` — reads transcripts, analyzes scores. Unchanged.

### What Changes

| File | Change |
|------|--------|
| `lib/MagicMountain/Bot/Agent.pm` | **New** — HTTP client wrapper |
| `lib/MagicMountain/Bot/Routine.pm` | **New** — game-loop orchestrator |
| `lib/MagicMountain/Bot/PushPolicy.pm` | Accept JSON hash; add `artifact.*` key path |
| `lib/MagicMountain/Bot/SellPolicy.pm` | Accept composite JSON state; use `decayed_value` |
| `lib/MagicMountain/Bot/SkillPolicy.pm` | Accept composite state (player + skills) |
| `lib/MagicMountain/Bot/PressurePolicy.pm` | Accept explicit context hash (no app access) |
| `lib/MagicMountain/Bot/BlackMarketPolicy.pm` | Accept JSON state with premium_mult |
| `lib/MagicMountain/Activity/Prospecting.pm` | Add `push_count` to `_artifact_view` |
| `lib/MagicMountain/Controller/Shed.pm` | Add `decayed_value` to `_item_view` |
| `lib/MagicMountain/Controller/Sessions.pm` | Bot login bypass via service token |
| `lib/MagicMountain/Service/BotRunner.pm` | **Deleted** |
| `lib/MagicMountain.pm` maintenance callback | Use Agent + Routine instead of BotRunner |
| `lib/MagicMountain/Command/simulate.pm` | Use Agent + Routine |
| `bin/walkthrough` | Full re-implementation using Agent + Routine |
| `t/bot_maintenance.t` | Adapt to new interface |
| `t/bot_simulate.t` | Adapt to new interface |
| `t/bot_skill_policy.t` | Adapt test data shape |
| `config/magic_mountain.yml` | Add `bot_service_token` key |

### Implementation Order

Each chunk is independently testable and mergable. Chunks 1-3 can
ship together as a unit (they define the interface). Chunks 4-7
retrofit consumers.

#### Chunk 1: Prerequisite controller changes

- `Activity/Prospecting.pm`: add `push_count` to `_artifact_view`
- `Controller/Shed.pm`: add `decayed_value` to `_item_view`
- `Controller/Sessions.pm`: add `X-Bot-Service-Token` bypass for
  bot accounts + rate limiting
- `config`: add `bot_service_token` key
- Test: verify push response includes push_count, shed JSON includes
  decayed_value, login with service token works for bot accounts

#### Chunk 2: `Bot::Agent`

- New file `lib/MagicMountain/Bot/Agent.pm`
- `req(GET|POST, $path, $body?)` with CSRF + service token handling
- All read/write alias methods
- Test: create agent, point at test server, log in with svc_token,
  make requests, verify JSON responses

#### Chunk 3: `Bot::Routine` + policy adaptation

- New file `lib/MagicMountain/Bot/Routine.pm`
- Adapt all five policy modules to JSON-shaped data
- `run_day` with all four phases (using Agent + policies)
- Transcript callback for event logging
- Test: with a test server + Agent, verify a full day runs through
  all phases. Test each policy with JSON-shaped test data.

#### Chunk 4: Retrofit simulation

- `simulate.pm` creates in-process app, creates Agent + Routine per bot
- Runs all days, collects transcript via callback
- Remove direct BotRunner call
- Update `t/bot_simulate.t`

#### Chunk 5: Retrofit live NPCs

- `MagicMountain.pm` maintenance: replace BotRunner with Agent + Routine
- Update `t/bot_maintenance.t`

#### Chunk 6: Retrofit walkthrough

- `bin/walkthrough` uses Agent for all HTTP, Routine for flow
- Assertions check JSON fields instead of HTML text
- Delete old scraping/hardcoded-path code

#### Chunk 7: Cleanup

- Delete `lib/MagicMountain/Service/BotRunner.pm`
- Remove any dead code references
- `make ci-check` passes
- `make cover && make report` for coverage gate

### Decisions (2026-07-19)

1. **Bot login**: Service token (`X-Bot-Service-Token` header)
   checked against `bot_service_token` config key. Bypasses bot
   account block and rate limiting. Explicit, auditable, secure.

2. **Simulation speed**: Use Mojo's in-process `server` attribute
   (`Mojo::UserAgent->new(server => $app)`) — full Mojo dispatch
   without TCP overhead.

3. **Walkthrough assertions**: Target JSON API fields, not HTML
   text. Same coverage, but asserts against the data structure
   rather than rendered output.

4. **Transcript format**: Keep the existing JSONL event format.
   `bin/analyze` should require minimal changes.

5. **Premium formula**: Already lives in
   `Activity::BlackMarket::_premium_multiplier`. No new service
   needed. The duplicate in BotRunner.pm is deleted with it.

6. **push_count**: Added to `_artifact_view` so the POST
   /prospecting/push response includes it for PushPolicy.

7. **decayed_value**: Added to Shed controller `_item_view` JSON
   output so SellPolicy can read the real value, not the estimate.

8. **PressurePolicy context**: Assembles enriched context from
   multiple Agent calls (GET /pvp + GET /game + config). Not
   a single endpoint response, which is fine — the Routine
   orchestrates data collection.
