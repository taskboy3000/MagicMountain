# Proposal: NPC Competitors (AI Bots in Live Seasons)

## Summary

Add policy-driven NPC competitors to live seasons. These bots prospect,
push, stop, and sell through the same activity dispatch as human players,
providing leaderboard pressure, market competition, and narrative texture.

The bot infrastructure already exists. The simulation framework
(`Bot::PushPolicy`, `Bot::SellPolicy`, `Command::simulate`) proves bots
can play the full game loop. Nine bot profiles are defined in
`content/bots.yml`. This proposal is about wiring that capability into
the live season loop.

---

## Motivation

The game is currently a solo push-your-luck exercise. The only interaction
is with faction-generated offers. NPC competitors would add:

1. **Leaderboard pressure** — bots score each day, giving the human player a
   target to beat. Rank is no longer guaranteed #1 by default.

2. **Market competition** — bots sell to factions too, consuming daily
   appetite slots and trait saturation pools. The player may arrive at the
   Bazaar to find their preferred faction already sated.

3. **Narrative texture** — the Town Crier can report bot achievements,
   collapses, and faction rivalries, making the world feel inhabited.

---

## Design

### Degree of Interaction: Market-Shared

Bots and human players draw from the same faction appetite, trait
saturation, and desperation pools. Bots do not interact with the player
directly — no counter-offers on the player's shed, no trade, no rivalries.
Interaction is mediated entirely through the shared market and leaderboard.

This is the smallest viable increment. Direct interaction could be explored
later but risks overcomplicating a push-your-luck game.

### Scheduling: All-at-Once at Rollover

Bots complete their full day immediately after maintenance. Execution order:

```
Maintenance fires
  → AP resets for all characters (player + bots)
  → Market dynamics reset (daily_intake = 0, days_since_purchase++)
  → Shed decay tick
  → Town Crier message generated
  → Bots play their day (prospect → push → stop → sell, one by one)
  → Day counter increments
```

Bots act after maintenance but before the player's day begins. This gives
the player first-mover advantage on a fresh market; bots pick over what's
left. It also avoids race conditions with concurrent player requests.

Staggered scheduling (bots act at intervals throughout the day via IOLoop)
could be added later but is not in scope for v1.

### Visibility

**Leaderboard** — bot names appear alongside human players in `GET /leaderboard`,
sorted by score, with rank assigned normally. No visual distinction between
bot and human rows (the leaderboard doesn't need to care).

**Town Crier** — the daily message may reference bot exploits:

> "Riveter pushed a thermal box to breakthrough, earning 52 scrap. The
> Syndicate is taking notice."

> "Zipper collapsed a void core. A bad day for the reckless."

Bot activity is also logged to the transcript with `actor => 'bot'` so the
UI can filter or style bot events differently if desired.

**Not visible** — bot shed contents, bot faction standing, bot AP count.
These are internal state. The player's visibility is the same as for any
other human competitor: leaderboard rank + score, plus whatever the Crier
chooses to narrate.

### Bot Count and Profiles

**4–6 bots per season.** Enough for variety without saturating faction
appetite pools.

Suggested composition for a season with one human player:

| Role | Profile | Behavior |
|------|---------|----------|
| Rival | `greed_desperate` (Risk Taker) | Pushes hard, sometimes collapses spectacularly. Scores high when lucky. |
| Specialist | `instability_loyalist` (Loyalist) | Focuses on one faction, building deep standing. Conservative pushes. |
| Hoarder | `value_hoarder` (Hoarder) | Stops early, sells conservatively. Rarely collapses. |
| Measured | `fixed_highest` (Measured) | Steady performer. Balanced push/sell decisions. |
| Wildcard 1 | Configurable, weighted random from pool | Keeps seasons fresh. |
| Wildcard 2 | Configurable, weighted random from pool | Keeps seasons fresh. |

Profiles are drawn from `content/bots.yml`. New profiles can be added
without code changes. The `--profile-weights` mechanism from the simulation
CLI can be reused to configure the season's bot roster.

### Bot Accounts and Characters

- Bot accounts are created at season start via the same account creation
  flow, flagged with `bot => 1` (or a `type` column on the Account model).
- Bot accounts are excluded from login (`POST /sessions` rejects bot
  accounts), session creation, and the human-facing leaderboard filter
  (if such a filter is desired).
- Bot characters are created via `GameOrchestrator::ensure_character` with
  the same defaults as human characters: 15 AP, skills at 0, score/scrap
  at 0.
- Bot characters persist normally in the character file. They participate
  in the same season, same leaderboard queries, same market dynamics.
- At season finalization, bot characters are archived alongside human
  characters as `SeasonRecord` rows.

### AP Budget

Bots use the same 15 AP/day as human players. If balance testing shows
bots scoring disproportionately, bot AP can be configured lower (e.g., 10)
via a `bot_action_points` config key without changing the core loop.

### Transcript

Bot game events are written to the same transcript file with an
`actor => 'bot'` field. The existing transcript query layer ignores this
field by default; it can be added to filters later if the UI wants to
distinguish bot from human narrative.

Alternatively, bot events could be written to a separate `transcript_bots`
file to keep the player transcript clean. This is a deployment choice, not
an architectural one.

---

## Technical Approach

### What Already Works

The simulation CLI (`perl -Ilib script/mountain simulate`) does all of this
offline:

1. Creates bot accounts and characters programmatically
2. Iterates through days: bots prospect, push (driven by PushPolicy), stop
   (driven by PushPolicy), then sell (driven by SellPolicy with faction
   selection, offer negotiation, counter-offer decisions, budget pressure)
3. Calls `Activity::Prospecting->dispatch()` and
   `Activity::MarketVisit->dispatch()` — the same methods the web
   controllers use for human players
4. Produces transcript output and final scoreboards

The architectures match. A bot character is indistinguishable from a
human character at the activity dispatch level.

### What Needs Building

1. **Bot account persistence** — an `is_bot` flag on `Model::Account`, or a
   separate `Model::Bot` table linked to account. The simulation creates
   ephemeral accounts; live bots need persistent ones that survive server
   restarts.

2. **Bot roster creation** — at season start (in `GameOrchestrator` or a
   dedicated service), create N bot accounts + characters for the new
   season, drawn from `content/bots.yml` with weighted random selection.

3. **Bot day runner** — a service that, given a bot character, runs the
   full daily loop:
   ```
   while AP >= 2:
       dispatch(prospecting, 'begin')
       evaluate push policy → push or stop
       dispatch(prospecting, 'stop')
       visit market → select customer → offer items → handle counters
   ```

   This exists in `Command::simulate` and would be extracted into a
   `Service::BotRunner` (or similar) that both the simulation and the
   maintenance callback can call.

4. **Maintenance integration** — wire `BotRunner::run_day($bot_char)` into
   the `on_maintenance` callback, after AP reset and market reset, before
   day increment.

5. **Crier bot awareness** — extend `Crier::generate` to optionally
   reference bot achievements when they're notable (first collapse of the
   season, breakthrough over N scrap, etc.).

6. **Bot login exclusion** — `POST /sessions` checks `is_bot` and rejects
   with 403.

### Extraction from simulate.pm

`Command::simulate` (442 lines) currently mixes three concerns:
- Simulation orchestration (day loop, season finalization)
- Bot account creation
- Bot day logic (prospect/push/sell loop)

The bot day logic should be extracted into a reusable service. The
orchestration remains in the command. Bot account creation moves to
the season-start flow. This extraction is backwards-compatible — the
simulation CLI continues to work.

### Pseudocode: on_maintenance Extension

```perl
# In the on_maintenance callback, after AP reset and market reset:

my $bots = $app->characters->find(sub {
    $_->{account_id} && $app->accounts->find_by_id($_->{account_id})->getCol('is_bot')
});

for my $bot_char (@$bots) {
    eval {
        $app->bot_runner->run_day($bot_char);
    };
    if ($@) {
        $app->log->warn("Bot $bot_char->{name} daily run failed: $@");
    }
}
```

Bot failures are logged and skipped — one buggy bot doesn't block
maintenance or other bots.

---

## Balance Considerations

| Risk | Mitigation |
|------|-----------|
| Bots drain faction appetite before player sells | Bots act *after* maintenance reset but player has the first real day — player gets first-mover advantage on fresh market pools |
| Bots score so high it's demoralizing | Profiles are tunable. Bot AP can be set lower than player AP. The rival profile can be seeded to score high but not unreachably so. |
| Bots score so low they're irrelevant | Simulation data shows the existing profiles produce competitive scores. Seed distribution to include one high-performer. |
| Bots don't adapt to market state | The SellPolicy already handles counter-offers, irritation, budget pressure, faction appetite, and trait saturation. They're reactive, not blind. |
| Too many bots saturate faction trait pools | 5 factions × 2-4 daily appetite slots = 10-20 slots. 1 player + 4-6 bots with ~2 sales each = 8-12 slots consumed. Comfortable margin. |
| All bots chase the same faction | Customer selection is faction-diverse (standing-weighted random plus loyalty access guarantee). Bots naturally spread across factions. |
| Bot shed grows unboundedly | ShedManager decay applies to bots too. Bots sell items each market visit; hoarder bots may accumulate but decay reduces value. |

---

## Non-Goals (v1)

- Staggered/real-time bot scheduling
- Bot-to-player direct interaction (counter-offers, trade, rivalries)
- Bot learning or adaptation (policies are fixed per profile)
- Bot skill purchases (bots use 0-skill baseline; skill trees are a human
  strategic choice)
- Bot visibility into other bots' state (each bot plays independently)
- Exposing bot shed contents to the player UI

---

## Success Criteria

1. Bots appear on the leaderboard alongside the human player, ranked by score.
2. Bot market activity consumes faction appetite and trait saturation normally.
3. Town Crier may report notable bot events.
4. The human player cannot log in as a bot.
5. The simulation CLI continues to work after extraction of shared bot logic.
6. Bot failures are logged and do not block maintenance or the human player.
