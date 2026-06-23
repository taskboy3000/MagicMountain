factional standing is a persistent value that changes during the season. That standing should be part of the story told about the player at the end of the season

> **Faction standing is not merely an unlock condition; it is part of the player character's seasonal biography.**

The player spent the season making ostensibly practical decisions: who pays best, who has interesting work, who can move a dangerous artifact, who might remember a favor. At season end, those transactions reveal what sort of person the settlement believes the player became.

## Why this is powerful

It preserves the separation between:

- **player intent:** “I wanted to win.”
    
- **social consequence:** “People noticed how I went about it.”
    

A player may not think of themselves as allied with the Faculty. But if they repeatedly sell anomalies into restricted collections, accept Faculty commissions, and recover objects from rivals, the end-of-season recap should recognize that pattern.

Likewise, a player who sold heating devices to LibreMount may have been chasing opportunities, not ideology. Yet the public dormitories are warmer because of those choices—and the inspection system may have collapsed around them.

# Faction Standing: Design Role

|Role|Description|
|---|---|
|Seasonal relationship state|Tracks how each faction regards the player during the current season.|
|Content selector|Opens faction-specific buyers, requests, encounters, invitations, accusations, and complications.|
|Social memory|Allows factions to acknowledge patterns in the player's behavior.|
|Recap input|Helps generate a personal ending that describes how the player participated in the temporary society.|
|Not character class|Standing does not make the player a formal faction member or determine identity in advance.|

## Standing should reset seasonally

I recommend that standing be seasonal, like score and scrap.

The new Mountain creates a new settlement with new people, pressures, and opportunities. A past-season record can persist as history or flavor, but it should not become a direct advantage in the next tournament.

This preserves the reset premise:

> Every season begins with opportunity; every season ends with reputation.

# Standing Is Not Morality

The recap should never translate standing into a moral score.

Avoid:

> You supported the corrupt Syndicate.

Prefer:

> Syndicate buyers knew to look for you before your salvage reached the open stalls. By the season's end, three merchants claimed they had financed your first successful haul. None agreed on which haul it was.

Avoid:

> You betrayed public access by refusing LibreMount.

Prefer:

> LibreMount notices never named you directly. Someone did paint your market stall on a warehouse door beside the words: ASK WHO GETS TO KEEP WARM.

The recap reports how the player became situated in the world. It does not issue a verdict.

# Standing and Buyer Choices

A disposition choice can create three kinds of effect:

|Effect|Meaning|
|---|---|
|Immediate payment|The personal, leaderboard-facing reward.|
|Faction influence|The artifact's contribution to the faction's power in the settlement.|
|Personal standing|How the receiving faction, and sometimes its rivals, come to regard this specific player.|

These should scale with artifact significance.

|Sale Type|Standing Effect|
|---|---|
|Routine low-value sale|Minimal or none; perhaps counted as background pattern.|
|Repeated sales to same faction|Recognition accumulates.|
|High-value or behaviorally unusual artifact|Significant standing change.|
|Artifact central to environmental crisis|Major standing and narrative impact.|
|Publicly contested artifact|Receiving faction notices; rivals may notice too.|

# The Player's Standing Need Not Be Simple

Standing should not merely be “likes/dislikes.” Over time, a faction may interpret the player in specific ways:

|Faction|Positive Interpretation|Negative or Complicated Interpretation|
|---|---|---|
|Revelationists|Provider of signs, trusted finder, respectful intermediary|Profiteer, desecrator, false witness|
|Purifiers|Responsible handler, reliable surrender source|Hazard dealer, reckless enabler, repeat offender|
|The Faculty|Useful supplier, reliable observer, favored procurer|Untrained meddler, provenance destroyer, embarrassing necessity|
|The Syndicate|Reliable seller, profitable partner, favored source|Price problem, unreliable operator, competitor|
|LibreMount|Access ally, lock-breaker, practical liberator|Hoarder, permit-lover, market collaborator, would-be custodian|

Mechanically, these can remain simple for a long time. Narratively, they let the end recap feel personal.

# End-of-Season Personal Recap Structure

A player recap could combine five layers:

|Recap Layer|Example Content|
|---|---|
|Competitive result|Final rank, score, largest sale, notable streak or collapse.|
|Salvage identity|Cautious operator, notorious gambler, anomaly specialist, practical supplier, dangerous tinkerer.|
|Faction standing|Which factions relied on, distrusted, courted, or resented the player.|
|Significant choices|A few high-value or contested artifact sales and their downstream effects.|
|World outcome connection|How the player's behavior participated in the faction-dominant final settlement.|

## Example: Faculty-connected player

> You finished fourth, with a reputation for surrendering devices only after they began doing something inconveniently interesting.
> 
> The Faculty recorded your name in three separate acquisition ledgers and spelled it differently in each. Their restricted annex contains at least seven objects recovered through your work, including one heating unit that has not warmed anything since the day you sold it.
> 
> When the Mountain vanished, a junior lecturer left a sealed request at your former stall: if the Mountain should appear again, she would prefer that you contact her before anyone responsible finds out.

## Example: Syndicate-connected player

> You finished second. Nobody in the market could agree whether you were lucky, skilled, or merely willing to sell quickly enough that the object's later problems became someone else's concern.
> 
> Syndicate brokers considered you dependable. By the end of the season, your name appeared on offers you had never authorized and on a warming-device warranty you certainly had not written.
> 
> When the Mountain disappeared, two lenders claimed you owed them money. Three others offered you credit for next season.

## Example: LibreMount-connected player

> You finished ninth, though substantially more of your work remains visible than the standings suggest.
> 
> The public sleeping hall still contains a heating unit you released through LibreMount. It warmed forty people through the last cold nights and emitted an unexplained clicking sound whenever someone attempted to place a warning placard nearby.
> 
> Your name was spoken warmly at the free salvage tables and less warmly among people whose locked storage did not remain locked.

## Example: Purifier-connected player

> You made less from hazardous artifacts than several of your rivals. You also spent fewer mornings explaining smoke.
> 
> Purifier crews credited you with surrendering four proscribed units, including the one recovered from behind the cookhouse shortly before its casing opened by itself. The cookhouse owner does not share their gratitude.
> 
> When the Mountain vanished, an inspector returned your final permit stamped SAFE FOR NOW.

## Example: Revelationist-connected player

> You never claimed that the artifacts meant anything. Other people noticed that the most memorable ones often passed through your hands.
> 
> Revelationist hostels displayed three objects you recovered. One produced warmth. One produced light. One produced neither after the second week, though pilgrims continued to report improvements in its presence.
> 
> On the last evening before the Mountain vanished, someone left a bowl of stew outside your stall with a note thanking you for not asking too many questions.

# Standing and the World Recap

The **personal recap** says how factions perceived the player.

The **world recap** says what the settlement became.

They should interact, but not collapse into the same thing.

For example:

- The Syndicate may dominate the settlement, while one specific player is remembered fondly by LibreMount.
    
- The Faculty may dominate, while the top-ranked player made most of their money selling to Revelationists.
    
- A player may contribute strongly to the dominant faction and later discover the season-ending result is not wholly comfortable.
    

This separation matters. The player can help create a world they did not intend.

# Design Note to Capture

Add this to the faction/salvage integration document:

```markdown
## Seasonal Faction Standing

Each player develops standing with factions during a season.

Standing changes primarily through:
- selling artifacts to faction buyers
- fulfilling faction requests
- resolving contested artifact events
- significant public choices involving faction interests

Standing represents:
- recognition
- access
- suspicion
- entanglement
- the player's visible pattern of participation in the settlement

Standing does not represent:
- formal membership
- moral alignment
- class selection
- repair skill
- direct combat or processing bonuses

During the season, standing may affect:
- available buyer offers
- special requests
- faction-colored interrupt events
- NPC reactions
- rival faction attention

At the end of the season, standing contributes to the player's personal recap.

The recap should describe:
- which factions knew the player
- what kinds of artifacts the player supplied or withheld
- what opportunities or conflicts followed
- how the player's practical decisions became part of the settlement's brief history

Faction standing resets with the season.

Records of past seasonal relationships may persist as history, but must not create a gameplay advantage in later seasons.
```

This is a high-value addition. It means that at the end of 30 days the game does not merely say, “You placed fifth.”

It says:

> “Here is who you became while trying to place first.”