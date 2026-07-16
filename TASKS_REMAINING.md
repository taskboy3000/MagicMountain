# Remaining Tasks — Bot Skill Purchasing + PvP

## Enhancement backlog (optional)

- [x] Add `simulate --pvp` flag to enable PvP in simulations
      (added `--pvp` flag to `simulate.pm`, set `pvp_enabled: 0` in `magic_mountain.yml`)

- [x] Add `policy_skill_purchase` check to `t/bot_simulate.t` transcript verification
      (added field verification in subtest 5)

- [x] Fix transcript routing leak in maintenance handler (`MagicMountain.pm`)
      (bot_runner->transcript restore now runs outside the `if (@$bot_chars)` block,
      preventing permanent transcript leakage to bot transcript)
