# ProspectBoy 3000

A multiplayer, seasonal push-your-luck web game. Players extract strange
artifacts from a mysterious mountain, destabilize them for greater value
(risking catastrophic collapse), and sell to competing factions before the
season ends.

Built with Mojolicious (Perl). See `GAME_ARCHITECTURE.md` for the full design
specification, `AGENTS.md` for codebase conventions, and `docs/` for design
reference. All configurable fields for `magic_mountain.yml` are documented
in `docs/TUNING.md`.

## Deploying behind a reverse proxy

The game listens on `http://localhost:9000` and must be placed behind a reverse
proxy (Apache, nginx, etc.) that terminates TLS and proxies to the backend.

**Apache example** — mount the game at a sub-path like `/gameshelf/magic_mountain`:

```apache
ProxyPreserveHost On
ProxyPass /gameshelf/magic_mountain/ http://localhost:9000/gameshelf/magic_mountain/
ProxyPassReverse /gameshelf/magic_mountain/ http://localhost:9000/gameshelf/magic_mountain/
RequestHeader set X-Forwarded-Prefix "/gameshelf/magic_mountain"
```

The `X-Forwarded-Prefix` header tells the application what path it is mounted
under. A `before_dispatch` hook in `MagicMountain.pm` uses the Mojolicious
Cookbook recipe to split the prefix from the request path and move it to the
base URL, so that:

- Routes match against the clean path (without the prefix)
- `url_for('route_name')` generates URLs with the prefix, e.g.
  `url_for('game')` → `/gameshelf/magic_mountain/game`

**Without the header** — direct access on `localhost:9000` — the app behaves
identically; no prefix is applied.
