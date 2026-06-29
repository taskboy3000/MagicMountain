# Random Events — Open Design Questions

Captured during review of `docs/Events_v2.md`. To be resolved before
implementation begins.

---

## 1. Condition Registry Design

### 1a. Context shape

The condition registry receives a single `$ctx` hashref, but prospecting
events and sales events need different context keys:

| Prospecting context | Sales context |
|---------------------|---------------|
| `artifact` | `customer` |
| `season` | `season` |
| `standing` | `standing` |
| `faction_state` | `faction_state` |
| — | `current_customer` |
| — | `outcome` |

**Option A: Union context** — single hashref with all possible keys.
Prospecting conditions simply never reference sales keys. Simple but no
compile-time safety; a prospecting condition that reads `outcome` would
silently get `undef` and likely pass the condition when it shouldn't.

**Option B: Typed contexts** — two separate hashes (`prospecting_ctx`,
`sales_ctx`). The `draw()` method passes the correct one based on pool.
Conditions are implicitly bound to a pool. Safer but adds a parameter to
the registry lookup.

### 1b. Static vs. instance registry

The spec shows `my $CONDITIONS` as a package lexical:

```perl
my $CONDITIONS = {
    artifact_stage_unstable => sub ($ctx) { ... },
};
sub _check_condition ($self, $name, $context) {
    my $check = $CONDITIONS->{$name} or return 0;
    return $check->($context);
}
```

**Option A: Static** — Shared across all instances. Tests cannot inject
mock conditions without monkey-patching. Simple, fast.

**Option B: Instance accessor** — The registry is a `has` attribute with a
builder that returns the static hash:

```perl
has conditions => sub { $CONDITIONS };
```

Tests override by constructing with a custom registry:
```perl
Service::RandomEvents->new(conditions => { custom => sub { 1 } });
```

More flexible, follows the existing Mojo::Base accessor pattern.

### 1c. Condition registration pattern

The spec says: "Adding a condition means adding one entry to `$CONDITIONS`
and one line in the test file."

Do we want a formal registration mechanism (e.g.,
`RandomEvents->register_condition(name => sub { ... })`) or just editing
the hash? A registration method would let modules register their own
conditions at startup (e.g., `MarketVisit` registers sales-specific
conditions, `Prospecting` registers prospecting ones). This keeps
conditions colocated with the domain logic they test. But it's more
infrastructure.

### 1d. Condition naming convention

Current names are snake_case and describe the predicate:
`artifact_stage_unstable`, `faction_days_since_purchase_gte_3`.

Should there be a namespacing convention to prevent collisions across
pools? E.g., `prospecting__artifact_stage_unstable` vs.
`sales__outcome_match`. Or are pool-scoped names sufficient?

---

## 2. Prompt Flow

### 2a. Event choice: dispatch vs direct call

Should `event_choice` go through the Activity's transition-based
`dispatch()` method, or be handled as a direct method call?

**Via dispatch** — consistent with all other user actions, but
`event_choice` is not a state-machine transition (it doesn't change phase).
Listed explicitly in transition tables as a concession to consistency.

**Direct call** — the controller calls
`$activity->resolve_event_choice($char, choice => ...)` directly, bypassing
`dispatch()`. More honest (it's not a transition) but breaks the dispatch
pattern and may surprise readers.

### 2b. Pending event expiration

If the player never responds to a prompted event (e.g., navigates away),
the `pending_event` column remains set. On the next action, should the
activity:
- Reject the new action (error: "resolve pending event first")?
- Silently clear the pending event and proceed?
- Auto-decline the pending event?

The first option is safest but can deadlock a player if the UI fails to
display the prompt. The second is forgiving but may confuse if effects
were expected. The third is a reasonable middle ground but requires
tracking an expiration.

---

## 3. Prompt Model: Bare Prompt vs. Full Choice

The current `prompt` field is a simple yes/no: accept (apply effects) or
decline (nothing). Two open questions:

### 3a. Should declining ever have a cost?

If every "no" is free, players will always decline ambiguous prompts,
making them feel like decoration. But if declining has a cost, the
feature becomes punitive.

### 3b. Should events ever offer two meaningful alternatives?

Example: "Unstable pocket detected. [A] Extract carefully (-2 instability,
-1 value) or [B] Push hard (+3 value, +3 instability)." This is closer to
the heavier `docs/Events.md` interrupt model. If we want this, the
infrastructure changes significantly (multiple effect blocks, labels, etc.)

---

## 4. Event Frequency Tuning

The spec defines `weight` per event for relative probability, but doesn't
address absolute frequency. Questions:
- What fraction of actions should trigger an event? (10%? 25%?)
- Should there be a global cooldown to prevent event spam?
- Should events be more common early-season and taper off?
- How does the `weight` system interact with a desired event rate? (If
  weights total 100 and we want 20% event rate, the Service silently
  no-ops 80% of the time after selection, or we use `weight` as absolute
  percentage.)

The current algorithm (filter → weighted random → return or undef) means
the event rate is whatever the sum of weights happens to produce, adjusted
by how many events pass filters. This is hard to tune.

---

## 5. Effect Application Order

Multiple effects on a single event are applied in YAML declaration order.
Does this matter? For example:

```yaml
effects:
  - adjust_value: 4
  - adjust_instability: 2
```

Does `adjust_instability` ever depend on the artifact's value? Currently
no, but as effects grow, order could matter. Should we specify that effects
are applied in declaration order, or should they be idempotent/order-independent?

---

## 6. Bot Prompt Strategy

The spec says bots always `decline` prompted events. Is this sufficient?
A future bot profile might want:
- `aggressive` — always accept
- `cautious` — always decline (current)
- `analytical` — accept if net effect > 0

This affects whether the bot's `dispatch` wrapper accepts an optional
strategy callback or if we hardcode the behavior for now.
