# Plan: Pawn — Black Market Replacement

## What We're Doing

Replace the old Black Market with **Pawn** — a unified Activity (`Activity::Pawn`)
that both humans and bots use to sell banned items one-at-a-time. The old
BlackMarket code, MarketGate, daily gate, and bot policy module are deleted.
No migration — orphaned `black_market` activities will be cleaned up naturally
when the next season starts.

## Two-phase approach

**Phase 1: Strip out old Black Market.** Delete all Black Market code, patch
every referrer, verify the game compiles and runs. Bazaar enforces universal
ban (banned items get disabled "BANNED" buttons). No Pawn yet — banned items
are simply unsellable. Clean intermediate state.

**Phase 2: Add Pawn system.** Create `Activity::Pawn`, `PawnCalculator`,
`Controller::Pawn`, wire PAWN nav tab, restore the sell-banned-items channel.

---

## Design

### PAWN primary tab

- Always visible between BAZAAR and INTEL (after onboarding).
- **Disabled** when: shed has no banned items, or dominant faction has no
  `banned_traits`. Reason: "No restricted items".
- **Active** when: shed has ≥1 item matching `banned_traits`, AP ≥ 1.

### Flow

1. **Click PAWN** — free. Shows broker card (risk orientation flavor) + shed.
   Non-banned items disabled ("—").

2. **Click a banned item** → POST `/pawn/offer` → costs **1 AP** → immediate
   roll (no confirmation prompt — broker card already orients the risk).

3. **Result card** shows outcome with two buttons:
   - **Dismiss** → home dashboard
   - **Offer another item** → back to broker + shed (only if more banned
     items remain)

4. **Success**: `floor(decayed_value * premium_mult)` scrap + score.
   Premium uniform random from [2.0, 2.5, 3.0, 3.5].
   **Seizure**: Item lost, 0 scrap. Logged to BrokersCache.
   **SMUGGLING** skill reduces seizure chance (Level 4 reroll kept).

5. Last banned item sold → "closed" card → Dismiss → home.
   PAWN tab stays visible, becomes disabled.

### Bot behavior

Bots follow the exact same flow: one Pawn activity per item. The bot sees the
result card and can choose "offer next" or "dismiss." Bots always try to pawn
every banned item they own (same AP cost, same seizure risk).

---

## Phase 1: Strip out old Black Market

Goal: Delete all old Black Market code. Bazaar enforces universal ban (banned
items get disabled "BANNED" buttons). Banned items are unsellable — no Pawn
yet. Verify game compiles and runs in this state.

### 1a. Modify referrers (remove references to deleted code)

| File | Action |
|------|--------|
| `lib/MagicMountain.pm` | Remove `use BlackMarket`, `use MarketGate`. Remove `has black_market`, `has market_gate`. Remove 3 BlackMarket routes. Remove maintenance reset of `black_market_opportunity_offered_today`. |
| `lib/MagicMountain/Controller.pm` | Remove `can('black_market')` fallback in `_active_activity_type`. Also remove `return 'black_market'` type check — orphaned activities return undef, character appears idle. This prevents a crash where Nav.pm would try to look up `$FRAGMENT_URL{black_market}` which no longer exists. |
| `lib/MagicMountain/Controller/Nav.pm` | Remove `black_market` entries from `%SECONDARY` and `%FRAGMENT_URL`. Remove `$view eq 'black_market'` context block. |
| `lib/MagicMountain/Service/Navigation.pm` | Remove `black_market => {...}` from `%BASE_TAB`. Remove `black_market => 'bazaar'` from `TAB_ID_FOR`. Remove `$view eq 'black_market'` from `resolve_view`. |
| `lib/MagicMountain/Service/BotRunner.pm` | Remove `use BlackMarketPolicy`. Remove entire Black Market phase block. Remove `$did_black_market` variable and wrapping `if`. Bots simply skip banned items for now (no pawn path until Phase 2). |
| `lib/MagicMountain/Activity/MarketVisit.pm` | Remove `can('market_gate')` block + `all_items_banned` return. In `offer`, remove the `$customer->{faction_id} eq` guard — ban is universal. |
| `lib/MagicMountain/Model/Character.pm` | Remove `black_market_opportunity_offered_today` column + default. |
| `lib/MagicMountain/Controller/Shed.pm` | Add `banned_trait_lookup` computation (inline for Phase 1 — use season's `faction_climate` directly). Pass `banned` flag to `_enriched_items` (fragment path) AND `_item_view` (JSON path) so both render paths get the flag. Template uses `$item->{banned} // 0`. |
| `templates/components/salvage_ledger.html.ep` | Add disabled "BANNED" button for items with `$item->{banned}`. No `$pawn_active` yet. |
| `content/bots.yml` | Remove `black_market_policy` from both bot profiles. |
| `t/model_character.t` | Remove `black_market_opportunity_offered_today` from column list. |
| `.perltidy_file_list` | Remove 4 old entries for deleted files. |

### 1b. Delete old files

1. `lib/MagicMountain/Activity/BlackMarket.pm`
2. `lib/MagicMountain/Controller/BlackMarket.pm`
3. `lib/MagicMountain/Service/MarketGate.pm`
4. `lib/MagicMountain/Bot/BlackMarketPolicy.pm`
5. `templates/black_market/broker.html.ep`
6. `content/flavor/black_market.yml`

### 1c. Verify

- `make ci-check` passes
- Bazaar: banned items show disabled "BANNED" buttons
- Bots: run without errors, skip banned items
- No orphaned Black Market references in any `.pm` file

---

## Phase 2: Add Pawn system

### 2a. Create new files

#### `lib/MagicMountain/Service/PawnCalculator.pm`

```perl
sub premium_multiplier {
    my @tiers = (2.0, 2.5, 3.0, 3.5);
    return $tiers->[int(rand(scalar @$tiers))];
}
sub seizure_chance ($self, $decayed_value) {
    my $chance = 0.05 + ($decayed_value / 200) * 0.30;
    return $chance > 0.35 ? 0.35 : $chance;
}
sub apply_smuggling ($self, $char, $chance) {
    my $skill = $char->getCol('skill_smuggling') // 0;
    my $reduced = $chance - $skill * 0.05;
    return $reduced < 0.02 ? 0.02 : $reduced;
}
sub banned_trait_lookup ($self) {
    my $season = $self->app->active_season or return {};
    my $climate = $season->getCol('faction_climate') // {};
    my @banned = @{ $climate->{banned_traits} // [] };
    return +{ map { $_ => 1 } @banned };
}
sub has_banned_items ($self, $char) {
    my $lookup = $self->banned_trait_lookup;
    return 0 unless keys %$lookup;
    my $items = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );
    for my $item (@$items) {
        my $behaviors = $item->getCol('behaviors') // [];
        for my $b (@$behaviors) {
            return 1 if $lookup->{$b};
        }
    }
    return 0;
}
```

#### `lib/MagicMountain/Activity/Pawn.pm`

Activity subclass:
- `transitions`: `{ idle => ['offer'], result => ['dismiss', 'offer_next'] }`
- `_activity_type`: `'pawn'`
- `create`: defaults `type => 'pawn'`
- `offer($char, %params)`: takes `shed_item_id`, checks banned traits,
  deducts 1 AP, rolls seizure/sale, logs transcript, returns result view.
- `dismiss($char)`: deletes activity, clears `pending_activity_id`.
- `offer_next($char)`: resets to `idle` phase, keeps activity alive.

#### `lib/MagicMountain/Controller/Pawn.pm`

Thin dispatcher:
```
show        — GET /pawn (fragment or JSON). Renders broker + shed.
offer       — POST /pawn/offer. $activity->dispatch($char, 'offer', ...)
dismiss     — POST /pawn/dismiss. $activity->dispatch($char, 'dismiss')
offer_next  — POST /pawn/offer_next. $activity->dispatch($char, 'offer_next')
```

#### `templates/pawn/broker.html.ep`

Three states:
- **Idle**: Risk orientation flavor, shed visible
- **Result**: "Sold for X scrap (2.5x)" or "SEIZED!" with Dismiss / Offer Another
- **Closed**: "Pawn shop closed" with Dismiss → home

#### `content/flavor/pawn.yml`

Flavor text for arrival, sale, seizure, closed states.

### 2b. Wire Pawn into the app

| File | Action |
|------|--------|
| `lib/MagicMountain.pm` | Add `use Pawn`, `use PawnCalculator`. Add `has pawn`, `has pawn_calculator`. Add 4 Pawn routes. |
| `lib/MagicMountain/Controller.pm` | Add `return 'pawn' if $row->{type} eq 'pawn'` to `_active_activity_type`. |
| `lib/MagicMountain/Service/Navigation.pm` | Add `pawn` to `%BASE_TAB` (active in all states). Add `pawn => 'pawn'` to `TAB_ID_FOR` map. `resolve_view` handles `pawn` like `market`. |
| `lib/MagicMountain/Controller/Nav.pm` | Add `pawn` to `%SECONDARY` (`pawn => 'shed'`), `%FRAGMENT_URL`, `%TAB_LABEL` (`pawn => 'PAWN'`), `%TAB_TO_VIEW` (`pawn => 'pawn'`). Add disabled override for PAWN. Add `_context_text` for `pawn` view. |
| `lib/MagicMountain/Controller/Shed.pm` | Replace inline banned lookup with `PawnCalculator::banned_trait_lookup`. Pass `pawn_active => 1` when `$type eq 'pawn'`. |
| `templates/components/salvage_ledger.html.ep` | Add `$pawn_active` branch: non-banned items disabled ("—"), banned items show "PAWN" offer button. |
| `lib/MagicMountain/Service/BotRunner.pm` | Add Pawn phase: bots iterate banned items, call pawn offer, evaluate result, offer_next or dismiss. |

### 2c. Tests

All new Test::Mojo integration tests:

| Test file | What it covers |
|-----------|----------------|
| `t/pawn_calculator.t` | `PawnCalculator` unit: `premium_multiplier` returns one of [2.0,2.5,3.0,3.5] (run 100x, assert only those values); `seizure_chance` formula correctness; `apply_smuggling` reduces chance by 5% per level; `banned_trait_lookup` reads from `faction_climate`; `has_banned_items` true/false |
| `t/pawn_controller.t` | Full lifecycle via Test::Mojo: GET `/pawn` returns fragment/JSON; POST `/pawn/offer` deducts AP, creates activity, returns result; POST `/pawn/dismiss` clears activity; POST `/pawn/offer_next` cycles back to idle; seizure path (mock rand); AP exhausted case returns error |
| `t/pawn_shed.t` | Shed fragment output in pawn context: `$pawn_active` set, non-banned items disabled, banned items have action_url pointing to pawn_offer |
| `t/pawn_nav.t` | PAWN tab present in nav; disabled when no banned items; active when banned items exist; TAB_ID_FOR and TAB_LABEL correct |
| `t/botrunner_pawn.t` | Bot with banned items uses Pawn phase; bot with no banned items skips to market |

---

## Unchanged

| File | Reason |
|------|--------|
| `Dominance.pm` | Still sets `banned_traits` on faction_climate |
| `Suggestion.pm` | Still shows banned trait advisories |
| `Model/BrokersCache.pm` | Seized items still logged here |
| `GAME_ARCHITECTURE.md` | Updated after implementation |
| `docs/TUNING.md` | Updated with new premium formula |
