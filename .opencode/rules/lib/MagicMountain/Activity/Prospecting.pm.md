# Activity::Prospecting.pm — Module Boundary Rules

> **Pre-check**: Before any edit, verify against the Authority Table in AGENTS.md.

## Authorized Attributes (constructor receives ONLY these)

```
✅ app     — for content YAML lookups and logging
✅ content — artifact specs, signal text, collapse text
✅ log     — debug logging
❌ character models, Market, Faction objects — check Authority Table
```

## Inherits From

`MagicMountain::Activity` — provides `dispatch()`, transition table, and
phase validation. Prospecting declares:

```perl
has phases      => sub { ['idle', 'processing', 'awaiting_buyer'] };
has transitions => sub {
    { idle => ['begin'], processing => ['push', 'stop'], awaiting_buyer => ['sell'] }
};
```

## Responsibilities
- Artifact push/collapse/breakthrough math
- Handle full prospecting lifecycle: begin → push/stop → sell
- Generate offers via Market (for `stop` action)
- Mutate character model fields and `pending_activity`
- Persist via `$char->save` (the character model's save method)
- Return `{ view => {...} }` for the controller to pipe to the template

## Constraints (MUST NOT)
- NEVER directly access State or any persistence layer. Persistence goes through
  the character model: `$char->save`.
- NEVER access Account model or PlayerAccount.
- NEVER reference `$self->transcript` — this attribute does not exist.
  Transcript enrichment is optional and always through an injected service.

## Input Contract — what dispatch() receives

```perl
$activity->dispatch($char, $action, %params)
#   $char    — Model::Character object. Mutate freely, then call $char->save.
#   $action  — 'begin', 'push', 'stop', or 'sell'
#   %params  — context values from the caller:
#       faction_id => $fid  # for 'sell' action
```

> Note: `influence` and `offers` are NO LONGER passed as %params from the
> controller. The activity calls Market directly for offer generation on
> `stop`, and reads influence from the character model or faction state.

## Output Contract — what dispatch() returns

```perl
{
    view => {
        ok     => 1,
        result => 'push' | 'collapse' | 'breakthrough' | 'stop' | 'start',
        artifact => { stage => 'strained', signal => 'It groans...', value => 24 },
        pending_sale => { offers => [...] },   # for 'stop'
        player => { turns_remaining => 6, scrap => 10, score => 10 },
    },
}
```

The `view` hashref goes directly to the HTTP response. The activity decides
what is player-visible. `instability`, `evolution_chance`, `push_count`,
and other internal math must never appear in `view`.

## Must Do
- Validate `faction_id` against stored offers in `pending_activity` for 'sell'
- Persist mutations via `$char->save` before returning
- Return only player-actionable data in the `view` hashref
- Never expose internal math (instability, evolution_chance) in `view`
