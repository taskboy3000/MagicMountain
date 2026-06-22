# Faction Snapshot History — Implementation Plan

## Goal

Persist daily faction influence snapshots so the leaderboard (or a dedicated
view) can display a timeline of faction dominance across a season.

---

## Design

### Data relationship

There are two distinct data structures — they serve different purposes:

| Data | Updated | Purpose | Lifetime |
|------|---------|---------|----------|
| `season.faction_state` | Every sale (live) | Customer generation, standing-weighted selection, Crier diffing | Per-season, cleared on finalization |
| `FactionSnapshot` | Daily (maintenance) | Historical timeline, end-of-season archive | Permanent |

**No double-sampling**: the FactionSnapshot is the *only* historical record.
The current end-of-season finalization calls `nullCol('faction_state')` and
the data is lost. With FactionSnapshot, we can reconstruct final faction
influence from the last snapshot row for each faction.

**Edge case**: sales that happen after the last daily maintenance but before
season finalization won't be in any snapshot. Two options:
- A) Accept this for MVP (last snapshot is "end of day N" and is close enough)
- B) Write a final snapshot during `Season::finalize` before clearing faction_state

Proceed with option B — it's one extra `->create()->save` call and eliminates
the gap entirely.

### Model: `lib/MagicMountain/Model/FactionSnapshot.pm`

```perl
package MagicMountain::Model::FactionSnapshot;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'season_id', 'day', 'faction_id', 'influence',
             'artifacts_received', 'intake_by_trait' ];
};
```

**File**: `$dataDir/faction_snapshots.json`

**One row per faction per day**. Append-only.

### App Attribute (`lib/MagicMountain.pm`)

```perl
has faction_snapshots => sub ($self) {
    MagicMountain::Model::FactionSnapshot->new(
        file => $self->dataDir . '/faction_snapshots.json',
        log  => $self->log,
    );
};
```

---

## Sequencing: When to Write

### During Daily Maintenance (`lib/MagicMountain/Maintenance.pm`)

The existing `on_maintenance` sequence is:

1. Increment `season.day`
2. Refresh character AP
3. Apply artifact decay
4. Generate Crier message (diffs `faction_state` vs `crier_snapshot`)
5. Update `crier_snapshot` to current `faction_state`
6. Log transcript event
7. Preserve activity rows

The snapshot write goes **between steps 5 and 6** — after the Crier has read
the current `faction_state` for its diff, but before the transcript log:

```
5. Update crier_snapshot to current faction_state
5b. Write FactionSnapshot rows: for each faction in faction_state,
    create a snapshot row with season_id, day, faction_id, influence,
    artifacts_received, intake_by_trait
6. Log faction_snapshot transcript event
```

Implementation:

```perl
my $fs = $season->getCol('faction_state') // {};
for my $fid (keys %$fs) {
    $self->app->faction_snapshots->create(
        season_id         => $season->getCol('id'),
        day               => $day,
        faction_id        => $fid,
        influence         => $fs->{$fid}{influence} // 0,
        artifacts_received => $fs->{$fid}{artifacts_received} // 0,
        intake_by_trait   => $fs->{$fid}{intake_by_trait} // {},
    )->save;
}
```

### During Season Finalization (`lib/MagicMountain/Model/Season.pm`)

In `finalize`, after computing SeasonRecords but before `nullCol('faction_state')`,
write one final snapshot batch so the last-minute sales are captured:

```perl
# Write final faction snapshots before clearing
my $fs = $season->getCol('faction_state') // {};
my @ranked = sort { $fs->{$b}{influence} // 0 <=> $fs->{$a}{influence} // 0 } keys %$fs;
for my $fid (keys %$fs) {
    $app->faction_snapshots->create(
        season_id  => $season_id,
        day        => $season->getCol('day'),
        faction_id => $fid,
        influence  => $fs->{$fid}{influence} // 0,
        artifacts_received => $fs->{$fid}{artifacts_received} // 0,
        intake_by_trait    => $fs->{$fid}{intake_by_trait} // {},
    )->save;
}
# ... then nullCol('faction_state')
```

#### Recap highlights from faction data

After writing the snapshots, compute a concise faction-influence summary for
each character's `SeasonRecord.story_highlights`:

```perl
# In the character loop, after building existing highlights:
my $faction_leaderboard = \@ranked;  # sorted faction_ids by influence desc
$highlights->{top_faction} = $ranked[0] if @ranked;
$highlights->{top_faction_influence} = $fs->{$ranked[0]}{influence} if @ranked;
$highlights->{factions_competing} = scalar @ranked;
```

This adds three fields to `story_highlights` — no new model, no audit trail,
just a concise snapshot of "who won the faction influence competition."

The existing `season_recap.t` test should verify these fields appear in the
recap JSON after finalization. Add assertions like:

```perl
is($hl->{top_faction}, 'syndicate', 'top faction in recap');
ok($hl->{top_faction_influence} > 0, 'top faction influence > 0');
```

---

## Querying: Frontend View

### Controller (`lib/MagicMountain/Controller/Leaderboard.pm`)

New action or extended response — return faction history grouped by faction:

```perl
sub factions ($self) {
    my $season = $self->app->active_season;
    return $self->render(json => { ok => 0, error => 'No active season' }, status => 404)
        unless $season;

    my $snaps = $self->app->faction_snapshots->find(
        sub { $_[0]->{season_id} eq $season->getCol('id') }
    );

    my %by_faction;
    for my $s (@$snaps) {
        push @{ $by_faction{ $s->getCol('faction_id') } }, {
            day                => $s->getCol('day'),
            influence          => $s->getCol('influence'),
            artifacts_received => $s->getCol('artifacts_received'),
        };
    }

    $self->render(json => { ok => 1, factions => \%by_faction });
}
```

### Route (`lib/MagicMountain.pm`)

```perl
$auth->get('/leaderboard/factions')->to('leaderboard#factions');
```

### Frontend

Add a "Faction Influence" section to the leaderboard page. For MVP, render
a simple per-faction table showing day-by-day influence growth. A canvas
line chart can come later.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Model/FactionSnapshot.pm` | New file |
| `lib/MagicMountain.pm` | Add `faction_snapshots` attribute + route |
| `lib/MagicMountain/Maintenance.pm` | Write snapshot rows between Crier and transcript |
| `lib/MagicMountain/Model/Season.pm` | Write final snapshots in `finalize` before clearing |
| `lib/MagicMountain/Controller/Leaderboard.pm` | Add `factions` action |
| `public/js/game.js` | Render faction timeline |
| `t/faction_snapshot.t` | Unit + integration tests |
| `t/maintenance.t` | Verify snapshots created during maintenance |
| `t/end_season.t` | Verify final snapshots written before clearing |
