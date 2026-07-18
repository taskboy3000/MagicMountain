# ProspectBoy 3000

A multiplayer, seasonal push-your-luck web game. Players extract strange
artifacts from a mysterious mountain, destabilize them for greater value
(risking catastrophic collapse), and sell to competing factions before the
season ends.

Built with Mojolicious (Perl). See `GAME_ARCHITECTURE.md` for the full design
specification, `AGENTS.md` for codebase conventions, and `docs/` for design
reference. All configurable fields for `magic_mountain.yml` are documented
in `docs/TUNING.md`.

Licensed under the [MIT License](LICENSE.txt).

## Deploying behind a reverse proxy

The game listens on `http://localhost:9000` and must be placed behind a reverse
proxy (Apache, nginx, etc.) that terminates TLS and proxies to the backend.

> **Project name / public name**: the codebase is *Magic Mountain*; the public
> facing deployment is *ProspectBoy 3000* (pb3k). Do not use `pb3k` as-is in
> production — replace it with a non-guessable path segment.

### Option A: X-Forwarded-Prefix header (recommended)

Apache — mount at something like `https://your.domain/pb3k/`:

```apache
ProxyPreserveHost On
ProxyPass /pb3k/ http://localhost:9000/
ProxyPassReverse /pb3k/ http://localhost:9000/
RequestHeader set X-Forwarded-Prefix "/pb3k"
```

The `X-Forwarded-Prefix` header tells the app what path it's mounted under.
A `before_dispatch` hook in `MagicMountain.pm` splits the prefix from the
request path and moves it to the base URL, so `url_for('route_name')`
generates correct prefixed URLs.

The backend receives a clean path (no prefix). Direct access on
`localhost:9000` also works with no prefix applied — the hook simply
returns early when the header is absent.

### Option B: Proxy forwards the full path

If you cannot inject the header, keep the prefix in the proxied path:

```apache
ProxyPreserveHost On
ProxyPass /pb3k/ http://localhost:9000/pb3k/
ProxyPassReverse /pb3k/ http://localhost:9000/pb3k/
```

The `before_dispatch` hook detects the prefix in the incoming URL path
and shifts it to the base. A root-to-`/pb3k/` redirect is recommended so
visitors landing on `https://your.domain/` end up at the prefixed URL:

```apache
RedirectMatch ^/$ /pb3k/
```

### Rules enforced at application level

- **All URLs must go through `url_for('named_route')`** — never hardcode a
  path string like `'/game'`. The only exception is the `/_G` global set in
  the layout template, which uses `url_for()` at render time. Hardcoded paths
  bypass the prefix and break behind the proxy.
- **Models never know about URLs.** Controllers compute image paths via
  `url_for('/images')` and inject them into model constructors.
- **Client-side navigation** uses the `_G` global (defined via `url_for()`
  in `<head>`) for all `fetch()` and `location` assignments.

### Health check

A plain `/health` endpoint returns `{ "ok": true }` with no auth or
database requirement — useful for load-balancer probes:

```
GET https://your.domain/pb3k/health
```
