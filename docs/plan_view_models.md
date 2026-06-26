# View Models: Artifact & Customer

> Also update `GAME_ARCHITECTURE.md` §4 (Module Boundary Table) to list
> `Artifact` and `Customer` as view model classes — they may hold
> presentation logic but must not implement domain rules or persist
> themselves.

---

## Goal

Replace ad-hoc stash key spraying with typed view model objects. Each
template receives a single object (`$artifact`, `$customer`) that owns
its display logic (value labels, portrait URLs, mood text, etc.). The
same objects are reusable across prospecting, market, shed, and the
game state endpoint.

---

## New Classes

### `MagicMountain::Artifact` (view model, not persisted)

```perl
my $a = MagicMountain::Artifact->new($activity->artifact);
# or from a ShedItem row:
my $a = MagicMountain::Artifact->new({
    id        => $item->getCol('artifact_id'),
    stage     => $item->getCol('stage'),
    value     => $item->getCol('decayed_value'),
    intro     => $item->getCol('intro') // $item->getCol('artifact_id'),
    signal    => $item->getCol('signal') // '',
    instability    => $item->getCol('instability'),
    max_instability => $item->getCol('max_instability'),
});
```

Methods:
- `->id`         — artifact identifier string
- `->value`      — numeric value (for engine use)
- `->value_label` — fuzzy tier label (via ValueTier)
- `->stage`      — stable / strained / unstable
- `->stage_badge_css` — CSS class for the stage badge
- `->intro`      — static flavor text
- `->signal`     — dynamic per-push flavor text
- `->icon_url`   — `/images/artifact_X.svg`
- `->instability`, `->max_instability` — push mechanic

Creation of a `ShedItem` from an artifact is done via a factory on the
model itself: `Model::ShedItem->from_artifact($char, $artifact)`. The
artifact view model has no awareness of persistence.

### `MagicMountain::Customer` (view model, not persisted)

```perl
my $c = MagicMountain::Customer->new($activity->customer);
```

Methods:
- `->faction_id`, `->faction_name`
- `->faction_icon_url`
- `->portrait_url` — includes mood suffix (happy/neutral/mad)
- `->disposition`
- `->irritation`
- `->pressure_state` — machine state string
- `->pressure_label` — display label ("COMFORTABLE", "OVER LIMIT")
- `->has_pending_counter`, `->pending_counter_value`
- `->last_message`, `->last_sale`

### `MagicMountain::ValueTier` (kept as-is)

Pure function: `f(number) → tier string`. No dependencies.

---

## Changes by Layer

### Step 1 — Artifact view model

| File | What |
|------|------|
| `lib/MagicMountain/Artifact.pm` | New class. Methods above. |
| `lib/MagicMountain/Activity/Prospecting.pm` | `stop` handler calls `ShedItem->from_artifact($char, $artifact)` to persist. |
| `lib/MagicMountain/Controller/Prospecting.pm` | Stash `artifact` object instead of 8 scalar keys. |
| `templates/prospecting/scan.html.ep` | Use `$artifact->value_label`, `$artifact->icon_url`, etc. |
| `lib/MagicMountain/Service/GameOrchestrator.pm` | `prospecting_view` returns Artifact hash for JSON. |

### Step 2 — Customer view model

| File | What |
|------|------|
| `lib/MagicMountain/Customer.pm` | New class. |
| `lib/MagicMountain/Controller/Market.pm` | Stash `customer` object instead of scattered keys. |
| `templates/market/negotiation.html.ep` | Use `$customer->faction_name`, `$customer->portrait_url`, etc. |
| `lib/MagicMountain/Controller/Game.pm` | `market_view` customer data. |
| `lib/MagicMountain/Controller/Nav.pm` | `_context_text` uses `$customer->pressure_label`. |

### Step 3 — ShedItem model enhancement

| File | What |
|------|------|
| `lib/MagicMountain/Model/ShedItem.pm` | Add `->value_label`, `->from_artifact($char, $artifact)` factory, optional shed-specific display methods (`->condition_label`, `->behaviors_list`). |
| `templates/home/dashboard.html.ep` | Iterate ShedItem objects directly; use `$item->value_label` instead of `value_min`/`value_max`. |
| `lib/MagicMountain/Controller/Home.pm` | Pass ShedItem objects to stash instead of anonymous hashes. |
| `lib/MagicMountain/Controller/Game.pm` | Same — pass ShedItem objects in `shed` response. |
| `lib/MagicMountain/Service/GameOrchestrator.pm` | `shed_items` returns ShedItem objects. |

### Step 4 — GAME_ARCHITECTURE.md

| File | What |
|------|------|
| `docs/GAME_ARCHITECTURE.md` | Add `Artifact`, `Customer` to the Module Boundary Table as view model classes. Update directory layout listing if present. |

---

### Step 5 — Cleanup

| File | What |
|------|------|
| Various templates | Remove stash keys that are now on the view model. |
| Tests | Update assertions for new JSON shapes (value_tier instead of value, etc.). |

---

## Cross-cutting Concerns

### JSON serialization

Controllers that render JSON (`Prospecting::show`, `Market::show`, `Home::show`,
`Game::show`) stash view model objects for the fragment path but need plain
hashes for JSON output. Each view model implements `TO_JSON` returning a
plain hashref, so Mojolicious serializes them natively:

```perl
# In Artifact.pm
sub TO_JSON ($self) {
    return { id => $self->id, stage => $self->stage, value_tier => $self->value_label, ... };
}
```

Controllers calling `render(json => $artifact)` work without explicit conversion.

### Customer: faction icon and pressure state

Customer is constructed from the customer hashref alone. Two lookups require
data outside that hash:

- **Faction icon**: Customer receives `faction_icon_url` as a plain string in
  its constructor (controller resolves it from `factions_data`).
- **Pressure state / label**: Customer receives `{state, display}` as an
  optional constructor arg. Controller passes the result of
  `$activity->budget_pressure_state($c)`.

---

## Dependencies

No circular dependencies. The view models import from ValueTier (a leaf module).
The Activity imports Artifact. Controllers import both.

```
ValueTier ← Artifact → Model::ShedItem
ValueTier ← Model::ShedItem (value_label)
Controller ← Artifact, Customer
```


