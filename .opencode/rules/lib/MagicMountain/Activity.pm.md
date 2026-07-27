# Activity.pm — Module Boundary Rules

> The base class for all expedition activities. Provides state-machine
> enforcement. Does NOT contain game math or artifact knowledge.

## Responsibilities
- Declare the transition table contract: `phases` and `transitions`
- Validate state-machine transitions before delegating to subclass handlers
- Provide `dispatch($char, $action, %params)` — the single entry point

## Authorized Attributes

```
✅ phases      — arrayref of legal phase names
✅ transitions — hashref of { phase => [legal next actions] }
✅ app         — application reference (for log access)
❌ character model reference (received as parameter)
❌ Market, Content, Faction objects
❌ any persistence object
```

## Subclass Contract

Subclasses must:
1. Declare `has phases` and `has transitions`
2. Implement one handler method per action in the transition table
3. Each handler receives `($self, $char, %params)`
4. Mutate character model fields and `pending_activity` via the passed `$char`
5. Call `$char->save` to persist changes
6. Return `{ view => {...} }` — the controller pipes `view` directly to the template

## Transition Enforcement

```perl
sub dispatch ($self, $char, $action, %params) {
    my $phase = $char->pending_activity->{phase} // 'idle';
    die "illegal transition: $phase → $action"
        unless grep { $_ eq $action } @{ $self->transitions->{$phase} // [] };

    return $self->$action($char, %params);
}
```

**Invariants**:
- The transition table is checked on every dispatch — bots cannot skip phases
- The subclass handler is only called if the transition is legal
- The character's `pending_activity->{phase}` is trusted as the current state
- Illegal transitions are a hard error (die), not a graceful 400 — the game
  should never generate an illegal request; if it does, it's a bug

## Constraints (MUST NOT)
- NEVER contain game math, artifact knowledge, or expedition-specific logic
- NEVER access content YAML (that's the subclass's job, via `app`)
- NEVER hold a reference to the character model (received per-call)
- NEVER persist directly to any file or database
- NEVER access domain models (`$self->app->seasons`, `$self->app->characters`,
  etc.) from the base class. External data (current day, season state) must be
  received as method parameters from the caller.
- NEVER define methods that reach into `$self->app` for game state. If a method
  needs external data, add a parameter and have the caller pass it.
