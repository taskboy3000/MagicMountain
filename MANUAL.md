# Magic Mountain — Player Manual

## Introduction

Magic Mountain is a multiplayer seasonal game of extraction, risk, and negotiation.
You are a salvager operating in the shadow of a mountain that produces strange
artifacts — remnants of an old world that no one fully remembers. Your tools are
a rugged field PDA called the **ProspectBoy 3000 (PB3K)**, a shed, and your wits.

Each season runs for a fixed number of days. Your goal: accumulate the highest
total sale value by the time the season ends. Every day brings a fresh allocation
of action points. What you do with them is up to you.

---

## The ProspectBoy 3000 (PB3K)

The PB3K is your primary interface. It is not a game menu — it is an in-universe
device recovered from the old world. Every screen, panel, and button is framed as
a function of this instrument.

The device screen is divided into:

- **Status strip** (top): Your callsign, current scrap, score, action points, and
  the current season day.
- **Primary content area**: The main panel for whatever you are doing —
  prospecting, negotiating, reviewing your shed.
- **Secondary content area**: A side panel for reference information, faction
  registry, or account settings.
- **Navigation bar**: Tabs for the main activities — PROSPECT, BAZAAR, INTEL,
  CERTS.
- **Context bar** (bottom): Situational messages from the PB3K's analysis
  routines.

The PB3K communicates in the dry, operational tone of a field instrument. It
reports measurements and observations. It does not speculate, comfort, or warn
you in emotional terms. When it says "Instability rising," it means the
instrument has measured an increase — not that you are in danger.

---

## Getting Started

### Joining a Season

When you first connect, the PB3K will check for an active season. If one is
running, you will be assigned a character and placed at the mountain. If no
season is active, you will see a waiting screen until the next season begins.

### The Daily Cycle

Each game day, your action points are fully refreshed. Unused points are lost —
there is no banking. The day advances on a schedule determined by the server
administrator. At day rollover:

- Action points reset to maximum
- Artifacts in your shed age and may decay in value
- Faction demand and market conditions update
- The Crier (the PB3K's news feed) may report on faction activity

### Action Points

Every activity costs action points. Prospecting, visiting the Bazaar, and other
operations consume from your daily pool. Managing this budget is the core
strategic decision you make each day.

---

## The Core Loop

### 1. Prospecting

Prospecting is how you acquire artifacts. You dispatch the PB3K's survey
sensors into the mountain's resonance field and recover a signal — an object
pulled from the debris of the old world.

When you begin a prospecting operation, the PB3K will present you with an
artifact. Each artifact has:

- **A type and behavior traits** — these determine which factions are interested
- **A current value** — what it might be worth at the Bazaar
- **An instability level** — a measure of how stressed the object is
- **A stage** — stable, strained, or unstable — indicating how close it is to
  collapse

The artifact's intro text and signal descriptions are the PB3K's sensor
readings. They tell you what the instrument observes, not what it means.

### 2. Pushing (Destabilization)

Once you have an artifact, you may choose to **push** it — applying energy to
destabilize the object in hopes of increasing its value. Each push:

- Increases the artifact's value
- Increases its instability
- May cause it to advance to a more dangerous stage

The risk is **collapse**: if instability exceeds the artifact's tolerance, the
object is destroyed and you recover nothing. You must decide when to stop
pushing and secure what you have.

Occasionally, a push may result in a **breakthrough** — a sudden, dramatic
increase in value. This is rare and cannot be reliably predicted.

### 3. Securing and Storing

When you stop prospecting (either because you chose to secure the artifact or
because the operation ended), the artifact is placed in your **shed**. From
there, you can take it to the Bazaar to sell.

---

## The Shed

Your shed is where artifacts wait between prospecting and sale. Artifacts in
the shed are not static — they **decay** over time. Each day, their condition
deteriorates and their estimated value may decrease.

The shed display shows each artifact's:

- Identifier and type
- Current condition (fresh, settling, fading)
- Estimated value range
- Days in storage

Decay is a fact of life. The longer you hold an artifact, the less it may be
worth. There is no penalty for selling quickly — only opportunity cost.

---

## The Bazaar

The Bazaar is where you sell artifacts to faction buyers. When you visit the
Bazaar with items in your shed, the PB3K connects you to a buyer from one of
the active factions.

### The Buyer

Each buyer represents a faction and arrives with:

- **A set of desired traits** — the faction's current interests
- **A budget** — how much they are willing to spend
- **An irritation level** — their patience with negotiation
- **A disposition** — their opening stance

### Negotiation

You offer an artifact from your shed. The buyer responds:

- **If the artifact matches their interests**: They will make an offer. You can
  accept, counter-offer, or send them away.
- **If the artifact does not match**: They may make a low offer or refuse.
- **Counter-offers**: You can propose a higher price. The buyer may accept,
  counter again, or walk away.
- **Standing pat**: If you have made a counter-offer, you can hold firm at your
  price. The buyer may accept or leave.

Each interaction affects the buyer's irritation. Push too hard and they may
storm off, ending the visit.

### Selling

When a sale completes:

- The artifact is removed from your shed
- You receive scrap (the currency) and score (the season-ranking metric)
- Your standing with that faction may change

You can send a buyer away at any time to end the visit and try again later with
a different buyer.

---

## The Factions

Five factions operate at the Bazaar. Each has its own interests, budget
patterns, and temperament. When a faction accumulates enough influence, it may
enter a period of **dominance**, which shifts market conditions.

### The Syndicate (SYND.8TE)

Commercial resellers. Volume buyers. The Syndicate moves product — they do not
care what it is as long as the margin works. They have broad interests and
consistent budgets.

*Known interests: thermal regulation, storage, food processing, power systems.*

**When dominant**: The Syndicate's commercial efficiency creates a market that
favors volatile and luxury goods. Some categories become restricted.

### LibreMount (LBR_MT.01)

A decentralized survivalist collective. LibreMount buys practical
infrastructure — the basics that keep a settlement running. Their budgets are
tight but their demand is steady.

*Known interests: thermal regulation, water, sanitation, medical response, power
systems.*

**When dominant**: LibreMount's practical focus creates stable, predictable
market conditions. No significant disruptions.

### The Faculty (FAC.LTY1)

An academic order. The Faculty's procurement is driven by archive gaps, not
resale value. Their interest patterns can be unpredictable, but their pricing
is consistent.

*Known interests: signal-type artifacts, revelation-class objects, field
manipulation, medical response.*

**When dominant**: The Faculty's academic priorities shift the market toward
signal and field artifacts. Some practical categories see reduced demand.

### The Purifiers (PURIF.RS)

A hazard-control collective. The Purifiers buy volatile materiel — the
dangerous, the unstable, the things no one else will touch. They pay for the
privilege.

*Known interests: force-type artifacts, instability-class objects, medical
response.*

**When dominant**: The Purifiers' aggressive containment protocols create demand
for volatile artifacts while restricting certain categories they deem hazardous.

### The Revelationists (RVL_IST.1)

Esoteric truth-seekers. The Revelationists believe the mountain speaks, and
they collect artifacts that might carry its message. Their budgets are modest
but their buyers are passionate.

*Known interests: revelation-class objects, signal-type artifacts, field
manipulation, transformation.*

**When dominant**: The Revelationists' influence shifts the market toward
esoteric and signal artifacts. Practical goods see reduced interest.

### Climate Effects

When a faction achieves dominance, the market enters a **climate** shaped by
that faction's priorities. Climate effects include:

- **Buyer trait biases**: Certain artifact traits become more valuable
- **Banned traits**: Some artifact categories may be restricted — the dominant
  faction will not buy them, and may block other buyers from doing so
- **Market mood shifts**: Buyer budgets, patience, and risk tolerance adjust
  according to the dominant faction's character

The Crier will announce when a faction achieves dominance. Pay attention.

---

## Skills

The PB3K can be upgraded with skill modules purchased from the CERT STORE.
Skills improve your capabilities in specific areas. Each skill has multiple
levels; higher levels cost more but provide greater benefits.

### GEO-SENSE (Prospecting)

Enhances artifact detection sensitivity. Higher levels reveal more information
about an artifact's traits and help you identify high-value targets.

### DEFRAG (Upcycling)

Optimizes the push protocol. Higher levels reduce instability growth during
pushing, improve value yield, and may increase the chance of breakthroughs.

### UP-CEL (Selling)

Augments the negotiation interface. Higher levels narrow appraisal variance,
reveal buyer irritation thresholds, and show the buyer's budget range.

### SHADOW-ROUTE (Smuggling)

Covert logistics module for the black market. Reduces the risk of seizure when
selling through unauthorized channels.

---

## The Black Market

Occasionally, the PB3K will receive an unsolicited transmission — a broker
offering to buy restricted goods at premium rates, no questions asked. This is
the **black market**.

Black market sales:

- Offer higher prices than the Bazaar
- Accept artifacts that may be banned by the dominant faction
- Carry a risk of **seizure** — the transaction can be intercepted, and you
  lose the artifact with no compensation

The SHADOW-ROUTE skill reduces seizure risk. You can also withdraw from a black
market offer at any time before committing.

---

## Rival Pressure (PvP)

Other salvagers operate on the mountain. You can spend resources to apply
**pressure** to a rival — disrupting their operations in a specific faction's
market. Pressure effects include:

- **Corner the market**: Reduce the price a rival receives from a faction
- **Spoil the lead**: Increase the cost of a rival's next prospecting operation
- **Outbid**: Intercept a rival's sale and claim a portion of the value

Pressure actions cost scrap and require you to have standing with the relevant
faction. Rivals can pressure you in return.

---

## Seasons and Tournament Structure

Each season is a tournament. All players start fresh with a new character.
At the end of the season:

- All characters are archived
- Season records are created showing final scores, rankings, and highlights
- Unsold artifacts in sheds are liquidated at a clearance rate
- A new season may begin

Your final score is determined by the total value of artifacts you sold during
the season. The player with the highest score wins.

---

## PB3K Interface Guide

### Reading the Status Strip

```
OPERATOR: <your callsign>    SCRAP: <currency>    SCORE: <rank value>    AP: <remaining>/<max>    DAY: <current>/<total>
```

### Navigation Tabs

- **HOME**: The default view. Shows the Crier feed and any active advisories.
- **PROSPECT**: Begin or continue a prospecting operation.
- **BAZAAR**: Visit the Bazaar to sell artifacts from your shed.
- **INTEL**: View rival players and apply pressure.
- **CERTS**: The CERT STORE — purchase skill upgrades.

### Secondary Tabs

- **FACTIONS**: Registry of active factions, their interests, and current
  standing.
- **ACCOUNT**: Account settings and character information.
- **?**: Orientation / help overlay.

### Common Actions

- **PROSPECT**: Begin a new prospecting operation (requires AP).
- **PUSH**: Destabilize the current artifact to increase its value.
- **STOP**: Secure the artifact and place it in your shed.
- **OFFER**: Present an artifact to a Bazaar buyer.
- **SEND AWAY**: Dismiss the current buyer and end the visit.
- **STAND PAT**: Hold firm at your counter-offer price.

---

## Administrator Guide

### Requirements

- Perl 5.28 or later
- Mojolicious (installed via CPAN)
- A UNIX-like operating system (Linux, macOS, BSD)

### Quick Start

```bash
# Install dependencies
cpan Mojolicious Modern::Perl YAML::XS File::Slurp UUID::Tiny

# Clone the repository
git clone <repository-url> magic_mountain
cd magic_mountain

# Start the development server
bash start.sh
```

The game will be available at `http://localhost:9000`.

### Configuration

The main configuration file is `magic_mountain.yml` in the project root. All
tunable values are documented in `docs/TUNING.md`.

Key configuration sections:

- **Session timeout**: How long before an idle session expires
- **Action points**: Default AP per day (overridable by season modifiers)
- **Season length**: Default number of days per season
- **PvP settings**: Enable/disable rival pressure, set costs
- **Rate limiting**: Request throttling settings

### CLI Commands

The game includes a command-line interface via `script/mountain`:

| Command | Description |
|---------|-------------|
| `create-account --name <username>` | Create a new player account |
| `delete-account --name <username>` | Delete an account and all associated data |
| `disable-account --name <username>` | Ban an account (prevents login) |
| `list-accounts` | List all player accounts |
| `reset-token --name <username>` | Reset an account's authentication token |
| `create-season --label <name>` | Create a new game season |
| `end-season` | Finalize the active season immediately |
| `advance-day` | Trigger daily maintenance (advance day, refresh AP, decay) |
| `init` | Reset all game data and create a fresh season |
| `simulate --days N --bots N` | Run a bot simulation for testing |
| `activity --lines N` | Show recent player activity from the transcript |
| `report` | Aggregate transcript stats for tuning analysis |

### Maintenance

The game runs daily maintenance automatically on a recurring timer. Maintenance
handles:

- Advancing the season day
- Refreshing action points for all characters
- Applying shed decay
- Generating Crier messages
- Creating faction snapshots
- Finalizing the season if it has exceeded its configured length

You can trigger maintenance manually with `script/mountain advance-day`.

### Deploying Behind a Reverse Proxy

The game listens on `http://localhost:9000` and must be placed behind a reverse
proxy (Apache, nginx, etc.) that terminates TLS.

**Apache example** — mount at a sub-path:

```apache
ProxyPreserveHost On
ProxyPass /gameshelf/magic_mountain/ http://localhost:9000/gameshelf/magic_mountain/
ProxyPassReverse /gameshelf/magic_mountain/ http://localhost:9000/gameshelf/magic_mountain/
RequestHeader set X-Forwarded-Prefix "/gameshelf/magic_mountain"
```

The `X-Forwarded-Prefix` header tells the application what path it is mounted
under. All URLs generated by the application will include this prefix.

**nginx example**:

```nginx
location /magic_mountain/ {
    proxy_pass http://localhost:9000/;
    proxy_set_header X-Forwarded-Prefix /magic_mountain;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### Production Deployment

For production use:

1. Set `MOJO_MODE=production` in the environment
2. Configure rate limiting in `magic_mountain.yml`
3. Place behind a reverse proxy with TLS termination
4. Consider using the pre-fork server for higher concurrency:
   ```bash
   MOJO_MODE=production script/mountain prefork -l http://*:9000
   ```

### Data Storage

All game data is stored as JSON files in the directory specified by
`MM_DATA_DIR` (defaults to `data/` under the application home). Each model
type has its own file:

- `accounts.json` — Player accounts
- `characters.json` — Game characters
- `seasons.json` — Season state
- `sessions.json` — Login sessions
- `shed.json` — Artifact inventory
- `transcript.jsonl` — Event log (newline-delimited JSON)

These files are human-readable but should not be edited while the game is
running. Always stop the server before making manual changes.

### Logging

The application logs to stdout by default. In production, redirect output to a
file:

```bash
MOJO_MODE=production script/mountain daemon -l http://*:9000 >> /var/log/magic_mountain.log 2>&1
```
