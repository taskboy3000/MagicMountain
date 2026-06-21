# Faction Standing — Implementation Plan

**Current state**: `character.faction_sales` and `character.standing` columns
exist but are never written. Customer generation is purely random. The
faction system is a content file with no runtime effect.

---

## Phase 1 — Standing Updates on Sale

**File**: `lib/MagicMountain/Activity/MarketVisit.pm`

Update `_do_sale` to track faction interactions. The sale handler already
knows which faction bought the item and whether it was a match (via the
`$intersect` flag computed in `offer`).

Standing formula:
- **Match sale**: `standing[faction_id] += 2` (good deal, customer happy)
- **Mismatch sale** (via settle): `standing[faction_id] += 1` (sale happened
  but reluctant)
- **Send away / customer leaves**: No change
- **Bonus +1** if `has_evolved` is true on the sold item (Faculty's premium)

`faction_sales[faction_id]` increments by 1 on every sale regardless.

The `offer` handler needs to pass the `$intersect` flag and item to
`_do_sale` so it can compute the correct standing delta:

```perl
sub _do_sale ($self, $char, $item, $value, $was_match) {
    ...
    my $fid = $self->customer->{faction_id};
    my $sales = $char->getCol('faction_sales') // {};
    my $standing = $char->getCol('standing') // {};

    $sales->{$fid}++;
    $standing->{$fid} += $was_match ? 2 : 1;
    $standing->{$fid}++ if $item->getCol('has_evolved');

    $char->setCol('faction_sales', $sales);
    $char->setCol('standing', $standing);
    ...
}
```

### Tests

Update `t/market_visit.t` to verify:
- Match sale: `faction_sales[fid]` incremented by 1, `standing[fid]` by 2
- Mismatch sale: `standing[fid]` incremented by 1
- Evolved artifact sale: bonus +1 standing
- `faction_sales` and `standing` reflected in character after sale

---

## Phase 2 — Season-Level Faction State

**File**: `lib/MagicMountain/Model/Season.pm`

Add `faction_state` column (hashref). Shape per §5.6:

```perl
{
    syndicate => {
        influence          => 245,  # cumulative sale value
        artifacts_received => 5,
        intake_by_trait    => { thermal => 3, power => 2 },
    },
    ...
}
```

Updated during `_do_sale` by loading the active season and mutating its
`faction_state`. This is a global aggregate — every player's sales
contribute.

### Where to update

The sale happens in `Activity::MarketVisit::_do_sale`. It has access to
`$self->app->seasons` and `$self->app->active_season`. Add after standing
update:

```perl
my $season = $self->app->active_season;
if ($season) {
    my $fs = $season->getCol('faction_state') // {};
    my $fid = $self->customer->{faction_id};
    $fs->{$fid}->{influence}          += $value;
    $fs->{$fid}->{artifacts_received}++;
    for my $t (@{ $item->getCol('behaviors') // [] }) {
        $fs->{$fid}->{intake_by_trait}->{$t}++;
    }
    $season->setCol('faction_state', $fs);
    $season->save;
}
```

### Test

`t/faction_state.t` — Create a season and a character, run a sale, verify
the season's `faction_state` reflects the sale value and artifact traits.

---

## Phase 3 — Standing-Weighted Customer Generation

**File**: `lib/MagicMountain/Activity/MarketVisit.pm`

Replace `_random_faction` with a function that weights faction selection by
the character's standing. Higher standing → more likely to see that faction.

```perl
sub _weighted_faction ($self, $char) {
    my $factions = $self->_factions;
    my $standing = $char->getCol('standing') // {};

    # Base weight 1.0; add 0.5 per standing point
    my $total = 0;
    my @weights;
    for my $f (@$factions) {
        my $w = 1.0 + (($standing->{$f->{id}} // 0) * 0.5);
        push @weights, { faction => $f, weight => $w };
        $total += $w;
    }

    my $roll = rand($total);
    my $cumulative = 0;
    for my $entry (@weights) {
        $cumulative += $entry->{weight};
        return $entry->{faction} if $roll < $cumulative;
    }
    return $factions->[0];
}
```

Also apply a small `base_multiplier` bonus based on standing:

```perl
my $mult_bonus = ($standing->{$faction->{id}} // 0) * 0.05;
$customer->{base_multiplier} += $mult_bonus;
```

### Test

Update `t/market_visit.t`:
- Character with standing 5 for a faction → that faction appears more often
  (statistical test over many runs, or deterministic with mocked rand)
- `base_multiplier` increases with standing

---

## Phase 4 — Standing Display in UI

**File**: `public/js/game.js`, `templates/game/show.html.ep`

Add a faction standing panel showing each faction the player has interacted
with:

```
Faction Standing
  The Syndicate      ★★☆☆☆  3 sales
  The Faculty        ★★★★☆  8 sales
  LibreMount         ★☆☆☆☆  1 sale
```

Stars derived from `standing[fid]` (0-5 mapping). Data already in the
`/game` JSON response (`player.faction_sales`, `player.standing`).

---

## Execution Order

```
Phase 1 — Standing updates in _do_sale + tests
  ↓
Phase 2 — faction_state column on Season + updates on sale + tests
  ↓
Phase 3 — Standing-weighted customer generation + tests
  ↓
Phase 4 — Faction standing UI panel
```
