# Bot Architecture: Mechanism/Policy Boundary

## Principle

Policies decide. Mechanisms execute. Never the other way around.

A policy takes JSON from the game server plus params from `bots.yml` and
returns a decision. It has no HTTP calls, no model access, no state
mutation, no awareness of `Agent`, `Routine`, or the game server
internals. It is a stateless function.

A mechanism is an orchestrator or transport layer. It calls the game
server API, passes JSON data to policies, and acts on the decisions.

## Layer Diagram

```
bots.yml  ──────────┬──────────┬──────────┬──────────┬──────────┐
                    │          │          │          │          │
                    ▼          ▼          ▼          ▼          ▼
              PushPolicy  SellPolicy  SkillPolicy  PawnPolicy  PressurePolicy
                    │          │          │          │          │
                    │    JSON data + params  (pure decisions)   │
                    │          │          │          │          │
                    └──────────┼──────────┼──────────┼──────────┘
                               │          │          │
                               ▼          ▼          ▼
                          Bot::Routine  (orchestrator loop)
                               │
                               ▼
                          Bot::Agent  (HTTP transport)
                               │
                               ▼
                        Game Server API
```

## Mechanism Layer

### `Bot::Agent` — HTTP transport only

- Thin `Mojo::UserAgent` wrapper
- One method per API endpoint, maps 1:1 to game routes
- Handles login, CSRF, service token, JSON encode/decode
- No conditionals, no decision logic, no policy awareness
- Returns decoded JSON hashref

### `Bot::Routine` — Phase orchestrator

- Owns the phase order and loop logic
- For each phase: calls Agent to discover state → calls Policy to
  decide → calls Agent to act
- Collects data across multiple API calls before passing to a policy
  (e.g., PressurePolicy needs /game + /pvp + config values assembled
  into one context hash)
- Handles result dispatch (switch on result strings, loop control)
- No business rules — those belong in policies

## Policy Layer

### Contract

Every policy follows this contract:

```
input:  (json_data_from_game, policy_params_from_bots_yml)
output: decision (scalar: boolean | hashref | undef)
```

No side effects. No HTTP. No imports of Agent, Routine, or app models.

### PushPolicy — when to stop pushing

```
PushPolicy::evaluate($push_response->{artifact}, $profile->{push_policy})
  → 1 (stop) | 0 (keep pushing)
```

Receives the artifact from the push response. Policy names:
`fixed_pushes`, `instability_cap`, `stage_guard`, `greed`,
`value_target`, `composite_and`, `composite_or`.

### SellPolicy — market engagement decisions

Four functions, each with its own dispatch table:

| Function | Input | Returns |
|----------|-------|---------|
| `accept_customer($customer, $params)` | customer data from GET /market | 1 | 0 |
| `should_offer_item($item, $params)` | item from GET /shed | 1 | 0 |
| `try_another($offer_resp, $customer, $params)` | result of last offer | 1 | 0 |
| `should_accept_counter($counter_value, $decayed_value, $params)` | counter + original | 1 | 0 |

Policy names: `hoarder`, `faction_loyalist`, `opportunist`,
`desperate`, `highest_offer`.

### SkillPolicy — which skill to buy next

```
SkillPolicy::decide($state, $policy_params, $skills)
  → { skill_id => '...' } | undef
```

Assembles state from `agent->game` (scrap, current levels) and
`agent->skills` (definitions + costs). Policy names: `immediate`,
`specialize`, `never`.

### PressurePolicy — PvP pressure

```
PressurePolicy->new->decide($context_hash)
  → { target_id => '...', faction_id => '...', effect_type => '...' } | undef
```

Context is assembled by Routine from agent->pvp, agent->game, and
config values. Not a single endpoint response — the orchestration
layer gathers the data.

- Stateless (Moo object for method dispatch only, no attributes stored)
- Uses `aggressiveness` from profile, not from a `name` dispatch

### PawnPolicy — when to use the pawn shop

(Not yet implemented. See `_pawn_phase` plan below.)

```
PawnPolicy::decide($state, $policy_params)
  → 'offer' | 'skip' | 'stop'
```

Where `$state` includes:
- `banned_items` — array of banned shed items (from GET /shed, items
  with `banned: 1`)
- `pawn_open` — whether pawn shop is accessible (from GET /pawn)
- `last_seizure` — whether the last pawn resulted in seizure
- `consecutive_seizures` — count of seizures this session

Policy params from bots.yml could include:
- `always` — pawn every banned item
- `value_threshold` — only pawn items above a minimum decayed_value
- `stop_after_seizure` / `stop_after_n_seizures` — stop pawning if
  seizure rate is too high
- `never` — never pawn (banned items stay in shed)

## Profile-Bound Parameters

All policy tuning lives in `content/bots.yml`. No hardcoded thresholds
in policy modules. Example profile with future pawn policy:

```yaml
- id: cautious_pawner
  push_policy: { name: "stage_guard", params: { stop_at: "unstable" } }
  sell_policy: { name: "opportunist", params: { max_irritation: 3 } }
  pawn_policy: { name: "value_threshold", params: { min_value: 15, stop_after_seizure: 1 } }
  skill_policy: { name: "immediate", params: { reserve: 30 } }
  pvp_aggressiveness: 0.10
```

## Adding a New Phase

To add a `_pawn_phase` to Routine:

1. **Mechanism**: New `_pawn_phase` sub in Routine.pm
   - Call `agent->pawn` to check availability
   - Call `agent->shed` to discover banned items (or a dedicated
     `agent->pawn_shed` endpoint)
   - Call `PawnPolicy::decide` with state + profile params
   - On 'offer': call `agent->offer_pawn($item_id)`
   - Handle result: 'sold' → log, 'seized' → track, loop or stop
   - On 'skip'/'stop': exit phase

2. **Policy**: New `PawnPolicy.pm` module
   - Pure function dispatch table
   - No HTTP, no Agent, no model imports
   - Receives only JSON data + policy params

3. **Agent**: New endpoint aliases
   - `sub pawn { GET /pawn }`
   - `sub offer_pawn($id) { POST /pawn/offer, { shed_item_id => $id } }`
   - `sub dismiss_pawn { POST /pawn/dismiss }` (maybe not needed if
     routine exits via AP exhaustion)

4. **Profile**: Optional `pawn_policy` key in bots.yml profiles

## Enforcement

- Policies MUST NOT import or reference `Bot::Agent`, `Bot::Routine`,
  any game model, `Mojo::UserAgent`, or make HTTP calls.
- Policies MUST NOT access `$app`, `$c`, or any controller/service
  object.
- Routine MUST NOT implement business rules inline — they go in
  policies.
- Agent MUST NOT contain conditionals beyond HTTP error handling.
