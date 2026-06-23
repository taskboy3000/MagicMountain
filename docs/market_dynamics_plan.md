# Market Dynamics — Implementation Plan

**Status**: Draft for review

## Motivation

Currently, faction pricing is static per faction (`base_multiplier`) plus a
linear standing bonus (+0.05× per standing point). This means:

- Artifact traits have no scarcity → a player who floods the market with
  the same type suffers no penalty
- Factions have no daily budget → an unlimited appetite on any given day
- There is no counter-balance to volume-selling strategies (desperate bots
  sell 25 artifacts per season with no price degradation)
- Players get no market signal about what's hot or oversaturated

## Design

### Three Levers

All three operate on the season's `faction_state`, which already tracks
`intake_by_trait` (cumulative trait counts per faction) and
`artifacts_received` (total per faction).

#### 1. Trait Saturation

Each trait sold to a faction increases that faction's saturation for that
trait. The effective offer multiplier is reduced:

```
effective_mult = base_multiplier * (1 - sat_rate * trait_count)
```

Where `sat_rate` is a global config parameter (default 0.02) and
`trait_count` is the number of artifacts with that trait sold to this
faction this season.

**Effect**: Selling 10 of the same trait drops the multiplier to
`1 - 0.02 * 10 = 0.80` of base. A faction with `base_multiplier=1.0`
would offer at 0.80× instead of 1.0×. This penalizes mono-trait
farming and rewards diversification.

**Cap**: `max_saturation_discount` (default 0.50) prevents prices from
going below 50% of the base multiplier.

#### 2. Daily Faction Appetite

Each faction has a `daily_appetite_base` (default 3). After receiving
`daily_appetite_base` artifacts in a single day, offers from that faction
get a `post_appetite_penalty` multiplier (default 0.5×).

**Effect**: A faction that's already bought heavily today offers less for
new items. Resets at daily maintenance. This prevents dumping 10 items
on the same faction in one day.

#### 3. Desperation Mechanic

Track `days_since_purchase` per faction. If a faction hasn't bought any
artifacts in `desperation_days` (default 3), their next customer visit
gets a `desperation_bonus` (default 1.3×) on their base multiplier.

**Effect**: Factions cycle between hungry and satiated. A faction you
haven't sold to in a while will pay a premium. This rewards rotating
between factions and makes sitting on inventory more strategic.

### Where the Levers Apply

All three modify the `base_multiplier` used in `offer()`:

```perl
# In MarketVisit.pm::offer(), when computing offer_value:

my $dyn_mult = $self->_dynamic_multiplier(
    $customer->{faction_id},
    $item->getCol('behaviors'),
    $season,
);

# Replace: $offer_value = int($decayed * $customer->{base_multiplier} * $match_mult);
# With:
$offer_value = int($decayed * $dyn_mult * $match_mult);
```

### Configuration

In `content/factions.yml`, per-faction:

```yaml
- id: syndicate
  # ... existing fields ...
  daily_appetite_base: 3       # items per day before penalty
  desperation_days: 3           # days idle before bonus
```

Global defaults in `MagicMountain.pm::defaultConfig`:

```perl
market_trait_saturation_rate  => 0.02,   # per-sale multiplier reduction
market_max_saturation_discount => 0.50,  # floor: 50% of base
market_post_appetite_penalty  => 0.50,   # multiplier after daily cap
market_desperation_bonus      => 1.30,   # multiplier after idle period
```

### State Storage

The season model's `faction_state` hash gains:

```perl
$fs->{$fid}->{daily_intake}     # reset each day in maintenance (narrative bucket)
$fs->{$fid}->{days_since_purchase} # incremented in maintenance, reset on sale
```

Both reset at daily maintenance. `daily_intake` resets to 0.
`days_since_purchase` increments by 1, then any faction that received
a sale that day resets to 0.

### Daily Maintenance Changes

In `MagicMountain.pm::maintenance` callback, after existing logic:

```perl
my $fs = $season->getCol('faction_state') // {};
for my $fid (keys %$fs) {
    $fs->{$fid}->{daily_intake} = 0;
    $fs->{$fid}->{days_since_purchase}++;
}
# Then for each character that made a sale today, reset their target
# faction's days_since_purchase. This is handled in _do_sale.
```

### Changes to `_do_sale`

After recording `intake_by_trait` and `artifacts_received`:

```perl
$fs->{$fid}->{daily_intake}++;
$fs->{$fid}->{days_since_purchase} = 0;
```

### Faction Interest UI Signal

To help players discover faction preferences, the game state endpoint
(`/game`) will include a faction interest summary when the player has
standing with that faction:

```json
"faction_insights": {
    "syndicate": {
        "known_interests": ["thermal", "storage"],
        "saturation_levels": {"thermal": 0.84},
        "appetite": "hungry"|"satisfied"|"desperate"
    }
}
```

This gives players actionable information without exposing raw tags.

---

## Implementation Order

1. **Faction dynamics helper** — Add `_dynamic_multiplier()` method to
   MarketVisit.pm. Reads saturation, daily intake, and desperation from
   season `faction_state`. Pure function, easy to test.

2. **Wire into offer()** — Replace `base_multiplier` reference with
   `_dynamic_multiplier()` call in the offer calculation.

3. **Record in _do_sale()** — Update `daily_intake` and
   `days_since_purchase` on each sale.

4. **Daily maintenance reset** — Reset `daily_intake` and increment
   `days_since_purchase` in the maintenance callback.

5. **Config** — Add global defaults to `MagicMountain.pm` and per-faction
   config to `content/factions.yml`.

6. **Tests** — Unit tests for `_dynamic_multiplier()`, integration tests
   for market visit with dynamics enabled.

7. **Game state UI** — Add faction insights to `/game` response.

8. **Simulation validation** — Run before/after sims to verify balance.

---

## Simulation Expectations

The dynamics should:

- Reduce desperate's advantage (volume selling now depresses prices)
- Increase opportunist's relative performance (fewer, better-matched sales
  avoid saturation penalties)
- Create price cycling (factions get hungry → pay premiums → saturate →
  prices drop → players switch factions → cycle repeats)
- Make loyalty more strategic (deep loyalty to one faction means accepting
  their saturation curve)

Target: All four non-hoarder strategies within 20% of each other (currently
~15% on the 30-day run). Slightly wider spread is acceptable because the
dynamics reward adaptability over single-strategy execution.
