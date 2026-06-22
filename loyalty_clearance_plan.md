# Faction Loyalist Premium + Hoarder Payout — Design Plan

## 1. Faction Loyalist Premium

### Problem

The loyalist bot only sells to one faction. Customer generation is random —
even with standing-weighted selection, the loyalist gets few matching customers
in a short season (avg 1.5 sales vs opportunist's 3.5). Without enough sales,
standing never accumulates, and the standing feedback loop (better prices, more
frequent customers) never kicks in.

### Solution: Loyalty Standing Bonus

Bonus standing for repeat business to the same faction (tracked by total
sales count, not streak). Applied in `MarketVisit::_do_sale` after the
existing standing delta and after `$sales->{$fid}++` increments:

```perl
# After $sales->{$fid}++ and existing delta:
my $total_to_faction = $sales->{$fid} // 0;
$delta++ if $total_to_faction >= 2;   # 2nd+ sale: extra standing
$delta++ if $total_to_faction >= 4;   # 4th+ sale: deep loyalty bonus
```

Effect:
| Total sales to this faction | Standing gain per sale |
|-----------------------------|------------------------|
| 1st sale | +2 (match) / +1 (settle) |
| 2nd–3rd | +3 / +2 |
| 4th+ | +4 / +3 |

This accelerates the standing feedback loop without changing the multiplier
math. A loyalist who sells 4+ times to their chosen faction gets +4 standing
per sale, which compounds into better customer frequency (+0.5 weight per
standing) and better prices (+0.05× per standing). The first sale is the
hardest — after that, loyalty builds on itself.

### Bot policy impact

The `faction_loyalist` bot now has a real path to viability. In 14+ day
seasons, it should match opportunist scores if it can get 4+ sales to its
faction. Bot policy code is unchanged — this is a core game mechanic.

---

## 2. Hoarder End-of-Season Payout

### Problem

Hoarder never sells. Score is always 0. This is a valid choice for a bot
profile but makes it uncompetitive in any leaderboard context.

### Solution: Clearance Sale

During `Season::finalize`, clearance is calculated and awarded BEFORE
SeasonRecords are created (between leaderboard ranking and record creation).
This ensures the boosted score is captured in the permanent archive.

**Sequence change** in `Season::finalize`:

```
1. Compute leaderboard rank (unchanged)
2. Calculate clearance: iterate shed items, sum decayed_value per character,
   multiply by 0.25 clearance rate, award to character scrap + score, save
3. Build SeasonRecords (captures boosted scores, adds clearance_bonus to
   story_highlights)
4–7. Unchanged (verify records, discard shed, delete chars, archive)
```

**Clearance calculation** — done DURING the shed discard loop, accumulating per
character before deleting:

```perl
# In the shed discard loop, track per-character clearance:
my %clearance;
for my $sid (keys %{ $app->shed->table }) {
    my $row = $app->shed->table->{$sid};
    next unless $row->{char_id};
    my $cref = $app->characters->table->{$row->{char_id}};
    next unless $cref && $cref->{season_id} eq $season_id;
    $clearance{ $row->{char_id} } += ($row->{decayed_value} // 0);
    delete $app->shed->table->{$sid};
}
$app->shed->save;

# Award clearance to characters (before they're deleted, before SeasonRecords)
for my $char (@sorted) {
    my $cid = $char->getCol('id');
    my $clr = int(($clearance{$cid} // 0) * 0.25);
    next unless $clr;
    $char->setCol('scrap', $char->getCol('scrap') + $clr);
    $char->setCol('score', $char->getCol('score') + $clr);
    $char->save;
}
```

Then when building SeasonRecords, the `$char->getCol('score')` already includes
the clearance. The clearance amount is added to `story_highlights`:

```perl
$highlights->{clearance_bonus} = $clr if $clr;
```

This models: "At season end, unsold shed artifacts are liquidated at 25% of
their last estimated value. Prospectors receive a closure payment."

For the hoarder bot with 15 unsold items averaging ~20 value each, that's
15 × 20 × 0.25 = 75 scrap/score — competitive but not dominant. For the
opportunist who sells most items, the clearance bonus is near zero.

### Bot policy impact

`hoarder` bots now earn non-zero scores. The payout is modest — never enough
to win a season, but enough that hoarding isn't a guaranteed loss. The "shoot
the moon" angle: if a hoarder happens to find a very high-value artifact
early and never sells it, the clearance rate applies to its full value.

---

## Summary

| Change | File | What |
|--------|------|------|
| Loyalty standing bonus | `MarketVisit.pm` `_do_sale` | +1 standing for 2nd+ consecutive same-faction sale, extra +1 at 4th+ |
| Clearance sale | `Season.pm` `finalize` | 25% of unsold shed value awarded at season end |
| Story highlights | `Season.pm` `finalize` | Add `clearance_bonus` to highlights |
