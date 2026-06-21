# Shed Controller & Inventory Filtering

### Shared: `_require_character` in Controller Base

**File**: `lib/MagicMountain/Controller.pm`

Extract the duplicated player-lookup pattern into the base class so every
controller can call `$self->_require_character`:

```perl
sub _require_character ($self) {
    my $player_id = $self->current_player;
    return undef unless $player_id;
    $self->app->characters->load;
    my ($char) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id }
    ) };
    unless ($char) {
        $self->render(json => { ok => 0, error => 'No character' }, status => 404);
        return undef;
    }
    return $char;
}
```

Then remove the duplicate in Skills.pm and use it in the new Shed controller.

---

## Phase 1 — `GET /shed` Endpoint

**File**: `lib/MagicMountain/Controller/Shed.pm` (new)

Returns all shed items for the current character with optional query-string
filters. Each filter is read via `$self->param('name')` — not
`$self->req->params->to_hash` — to keep the interface simple.

```perl
sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $all = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );

    my $filtered = _apply_filters($all, $self);
    $self->respond_to(
        json => sub {
            $self->render(json => {
                ok     => 1,
                shed   => [ map { _item_view($_) } @$filtered ],
                total  => scalar @$all,
                count  => scalar @$filtered,
            });
        },
        ...
    );
}
```

**Filters** (all optional, applied via query params):

| Param | Values | Effect |
|-------|--------|--------|
| `condition` | `fresh`, `settling`, `fading` | Only items in that condition stage |
| `artifact_id` | string (e.g. `thermal_box_001`) | Exact match on artifact type |
| `behavior` | string (e.g. `thermal`, `field`) | Items whose behaviors array includes this tag |
| `min_value` | integer | `estimated_value_min >= N` |
| `max_value` | integer | `estimated_value_max <= N` |
| `sort` | `value` (default), `age`, `artifact_id` | `value` sorts by `estimated_value_min` |
| `order` | `desc` (default), `asc` | Sort direction |

**Item view** (returned per item):

```json
{
    "id": "<uuid>",
    "artifact_id": "thermal_box_001",
    "condition": "settling",
    "days_in_shed": 3,
    "original_value": 24,
    "estimated_value_min": 12,
    "estimated_value_max": 18,
    "behaviors": ["thermal", "power"],
    "push_count": 2,
    "stage": "strained",
    "has_evolved": false
}
```

`original_value` is included so the player can see how much value has been
lost to decay. `decayed_value` and `instability` are internal and excluded.

**Route**: `$auth->get('/shed')->to('shed#index');`

### Test

`t/shed.t` — Create shed items for a character, verify:
- Returns all items with correct structure (including `original_value`)
- `condition` filter narrows results
- `artifact_id` filter matches exact type
- `behavior` filter matches trait tags
- `min_value`/`max_value` filter by estimate range
- `sort` and `order` control ordering
- Response includes `total` (pre-filter) and `count` (post-filter)
- Empty shed returns `shed: [], total: 0, count: 0`
- Unauthenticated request returns redirect

---

## Phase 2 — Shed UI Page

**File**: `templates/shed/index.html.ep` (new)

A standalone inventory page, linked from the game SPA. Shows the full shed
with filtering controls:

```
┌─────────────────────────────────────────┐
│  Shed Inventory  [← Back to Mountain]   │
├─────────────────────────────────────────┤
│  Filters: [condition ▼] [behavior ▼]    │
│  Sort: [value ▼] [desc]                 │
├─────────────────────────────────────────┤
│  thermal_box_001  settling  12-18 scrap │
│  void_core_001    fresh     20-30 scrap │
│  crystal_chime_001 fading     8-12 scrap│
│  ...                                    │
└─────────────────────────────────────────┘
```

Each item row links to or expands into a detail view (push history, decay
trajectory). Implemented as a static HTML page with JS fetching from `/shed`
with query params. No server-side rendering needed — just a container div
and a script tag.

**Route**: `$auth->get('/shed')->to('shed#index');` — `respond_to()` serves
HTML when `Accept: text/html`, JSON when `Accept: application/json`.

### Order

```
Phase 1.1 — Controller/Shed.pm with _item_view + filter logic
Phase 1.2 — Route + respond_to wiring
Phase 1.3 — t/shed.t tests
  ↓
Phase 2.1 — templates/shed/index.html.ep (JS-driven filter page)
Phase 2.2 — Link from game SPA to /shed
```

Verification:
```
prove -l t/shed.t
prove -l t/
```
