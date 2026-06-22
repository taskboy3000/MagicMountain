# Bot Policy Framework — Implementation Plan

## Goal

Replace the single hardcoded bot strategy in `Command::simulate` with pluggable
push and sell policies, loaded from YAML bot profiles. This enables mixed-
strategy populations for balance tuning and simulation analysis.

---

## Design

### Policy Modules

Two single-module dispatch tables:

- `MagicMountain::Bot::PushPolicy` — push decision dispatch
- `MagicMountain::Bot::SellPolicy` — sell decision dispatch

Each policy is a named entry in a dispatch hashref. No class hierarchy.

### Push Policies (`lib/MagicMountain/Bot/PushPolicy.pm`)

Interface: `should_stop($char, $artifact_view, $params) => 0|1`

Policies receive the full character model (`$char`), so they can read skill
levels via `$char->getCol('skill_upcycling')` to adjust behavior.

| Policy | Params | Logic |
|--------|--------|-------|
| `fixed_pushes` | `{ max => 3 }` | Stop after N pushes (`push_count >= max`) |
| `instability_cap` | `{ max => 5 }` | Stop when `artifact.instability > max` |
| `stage_guard` | `{ stop_at => "unstable" }` | Stop when `artifact.stage` matches target |
| `greed` | `{ prob => 0.7 }` | On each push, continue with prob P; stop with (1-P) |
| `value_target` | `{ min => 20 }` | Stop when `artifact.value >= min` |
| `composite_and` | `{ policies => [...] }` | Stop when ALL sub-policies say stop |
| `composite_or` | `{ policies => [...] }` | Stop when ANY sub-policy says stop |

Implementation approach — a dispatch table in `PushPolicy.pm`:

```perl
package MagicMountain::Bot::PushPolicy;
use Mojo::Base '-base', '-signatures';

my %POLICIES = (
    fixed_pushes    => sub ($char, $art, $p) { ($art->{push_count} // 0) >= ($p->{max} // 3) },
    instability_cap => sub ($char, $art, $p) { ($art->{instability} // 0) > ($p->{max} // 5) },
    stage_guard     => sub ($char, $art, $p) { ($art->{stage} // '') eq ($p->{stop_at} // 'unstable') },
    greed           => sub ($char, $art, $p) { rand() >= ($p->{prob} // 0.7) },
    value_target    => sub ($char, $art, $p) { ($art->{value} // 0) >= ($p->{min} // 20) },
    composite_and   => sub ($char, $art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 0 unless __PACKAGE__->evaluate($char, $art, $sub);
        }
        return 1;
    },
    composite_or    => sub ($char, $art, $p) {
        my @subs = @{ $p->{policies} // [] };
        return 0 unless @subs;
        for my $sub (@subs) {
            return 1 if __PACKAGE__->evaluate($char, $art, $sub);
        }
        return 0;
    },
);

sub evaluate ($char, $artifact, $policy) {
    my $name = $policy->{name} or die "push policy missing name";
    my $handler = $POLICIES{$name} or die "unknown push policy: $name";
    return $handler->($char, $artifact, $policy->{params} // {});
}
```

### Sell Policies (`lib/MagicMountain/Bot/SellPolicy.pm`)

Sell policies control three decision points in the market visit flow:

1. **`accept_customer`** — After `begin` generates a customer, should the bot
   proceed or `send_away` immediately? (`faction_loyalist` checks faction,
   others yes; `hoarder` is checked before the market loop, not via this)
2. **`should_offer_item`** — Before offering each shed item, should the bot
   bother? (`highest_offer` skips items below `min_value`, others yes)
3. **`try_another`** — After a `no_match`, should the bot try another item or
   stop? (`opportunist` stops on first mismatch, others keep trying)

| Policy | Params | accept_customer | should_offer_item | try_another |
|--------|--------|-----------------|-------------------|-------------|
| `opportunist` | `{}` | Yes | Yes | No |
| `desperate` | `{}` | Yes | Yes | Yes |
| `highest_offer` | `{ min_value => 10 }` | Yes | Only if `decayed_value >= min` | Yes |
| `faction_loyalist` | `{ faction => "syndicate" }` | Only if customer matches faction | Yes | Yes |
| `hoarder` | `{}` | N/A (checked pre-loop) | N/A | N/A |

```perl
my %ACCEPT_CUSTOMER = (
    hoarder          => sub ($char, $cust, $p) { 0 },
    faction_loyalist => sub ($char, $cust, $p) { ($cust->{faction_id} // '') eq ($p->{faction} // '') },
    default          => sub ($char, $cust, $p) { 1 },
);

my %OFFER_ITEM = (
    highest_offer    => sub ($char, $item, $p) { ($item->getCol('decayed_value') // 0) >= ($p->{min_value} // 10) },
    default          => sub ($char, $item, $p) { 1 },
);

my %TRY_ANOTHER = (
    opportunist      => sub ($char, $offer, $cust, $p) { 0 },
    default          => sub ($char, $offer, $cust, $p) { 1 },
);
```

The bot loop in `_run_bot_day` checks `hoarder` before entering the market
loop (skip entirely). For other policies, it enters, calls `begin`, then
checks `accept_customer` — if false, calls `dispatch($char, 'send_away')`
and ends the visit. `should_offer_item` skips individual items (moves to
next). `try_another` ends the visit after a no_match.

Transcript events: `policy_send_away` when a customer is rejected after begin,
`policy_skip_item` when an item is skipped below threshold, `policy_stop_offer`
when try_another returns false after a no_match.

### YAML Bot Profiles (`content/bots.yml`)

```yaml
- id: cautious_alice
  push_policy: { name: "stage_guard", params: { stop_at: "unstable" } }
  sell_policy: { name: "opportunist" }
  skill_profile: { prospecting: 1, upcycling: 0, selling: 0 }

- id: greedy_bob
  push_policy: { name: "greed", params: { prob: 0.8 } }
  sell_policy: { name: "highest_offer", params: { min_value: 15 } }
  skill_profile: { prospecting: 2, upcycling: 1, selling: 0 }

- id: hoarder_carol
  push_policy: { name: "value_target", params: { min: 25 } }
  sell_policy: { name: "hoarder" }
  skill_profile: { prospecting: 0, upcycling: 3, selling: 0 }
```

Each bot gets a profile assigned on creation. Profiles are assigned round-robin
through the available profiles. If fewer bots than profiles, each bot gets a
unique profile (no duplicates). When `--profile-weights` is given, weighted
random selection replaces round-robin.

### Transcript: Policy Identity

Each bot's events must be traceable to their policy profile. Two mechanisms:

### 1. `profile_id` in transcript events

Every bot event includes a `profile_id` field matching the profile from the
YAML config. Bot names remain `bot-001` for backward compatibility.

### 2. Policy decision events

Add new transcript event types for every policy decision:

| Event type | When fired | Fields |
|-----------|------------|--------|
| `policy_send_away` | Bot rejected customer after begin (faction_loyalist, wrong faction) | `reason` |
| `policy_stop_offer` | Bot stopped offering after mismatch (opportunist) | `reason`, `mismatches` |
| `policy_push_stop` | Bot stopped pushing per policy | `policy`, `params`, `stage`, `value`, `push_count` |

This makes every policy decision explicit in the transcript — analysis can
see "bot-003 stopped pushing because `stage_guard` triggered at unstable"
rather than inferring from the absence of further push events.

### 3. `sim_start` event records the full roster

```json
{
  "type": "sim_start",
  "bots": [
    { "name": "bot-001", "profile_id": "cautious_alice", "push_policy": "stage_guard", "push_params": {"stop_at": "unstable"}, "sell_policy": "opportunist" },
    { "name": "bot-002", "profile_id": "greedy_bob", "push_policy": "greed", "push_params": {"prob": 0.8}, "sell_policy": "highest_offer", "sell_params": {"min_value": 15} }
  ]
}
```

Analysis scripts can then:
- Filter events by `player.name` to get per-bot data
- Cross-reference `sim_start.bots` to map bot names to policies
- Run queries like "what was the average score for bots with `greed` policy?"

## Integration into `Command::simulate`

The `_run_bot_day` method is refactored to use policy evaluation:

**Prospecting**: After `dispatch($char, 'push')`, if the push succeeds, ask
the push policy `evaluate($char, $artifact_view, $push_policy)`. If it returns
true, call `dispatch($char, 'stop')` and move on.

**Selling**: After `dispatch($char, 'offer')`, check the result. If `sold`,
done. If `customer_left`, done. If `no_match`, ask the sell policy whether to
try another item (opportunist says no, desperate says yes, etc.). Currently
the bot tries all items — opportunist would stop after first mismatch.

The CLI gains a `--profile` flag:

```
--profile YAML_FILE    Bot profile definitions (default content/bots.yml)
--profile-weights "cautious_alice=3,greedy_bob=1"  Distribution weights
```

When `--profile` is used, `--skill-profile` is ignored (profile YAML defines
skills per bot). When `--profile` is not used, `--skill-profile` applies
uniformly as before, and bots use the default `stage_guard`+`opportunist`
strategy (current behavior, backward-compatible).

Profile assignment: when `--profile-weights` is given, bots are assigned via
weighted random selection. When omitted, profiles cycle round-robin through
the available profiles. If fewer bots than profiles, each bot gets a unique
profile (no duplicates).

---

## Files Changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Bot/PushPolicy.pm` | New — push decision dispatch |
| `lib/MagicMountain/Bot/SellPolicy.pm` | New — sell decision dispatch |
| `content/bots.yml` | New — default bot profile definitions |
| `lib/MagicMountain/Command/simulate.pm` | Replace hardcoded strategy with policy dispatch; add `--profile` flag |
| `t/bot_simulate.t` | Test policy evaluation directly |
| `t/bot_policies.t` | New — test YAML profile loading + mixed populations |

---

## Test Plan

- Unit test each push policy with known inputs, verify stop/continue decision
- Unit test each sell policy with mock offer results
- Test composite policies (and/or combinations)
- Integration test: simulate with 2 `stage_guard` + 2 `hoarder` bots, verify
  hoarders have lower score but more shed items at season end
- Verify `--profile` flag loads custom YAML, falls back to defaults
