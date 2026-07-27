# Market.pm — DOES NOT EXIST (Removed)

> **This module was removed during refactoring.** Market logic now lives in
> `MagicMountain::Activity::MarketVisit`. See boundary rules at
> `.opencode/rules/lib/MagicMountain/Activity/Prospecting.pm.md` and
> `lib/MagicMountain/Activity/MarketVisit.pm` for the actual implementation.

## What happened

The standalone `Market.pm` with `generate_offers()` was never implemented.
Offers are no longer generated at prospecting stop time. The selling flow is:

1. Player prospects an artifact (→ enters Shed)
2. Player visits the Bazaar via MarketVisit activity (`POST /market/begin`)
3. A customer is generated with `desired_behaviors`, budget, irritation
4. Player offers Shed items one at a time
5. Match/mismatch/counter-offer logic runs inside MarketVisit handlers
6. Sale removes item from Shed, awards scrap+score, updates standing

## If you are adding offer-generation logic

Put it in `Activity::MarketVisit`, not a standalone Market service. See
`lib/MagicMountain/Activity/MarketVisit.pm` for the customer generation,
negotiation, and sale flow.
