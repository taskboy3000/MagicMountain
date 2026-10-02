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

## Install

### PREPARE THE ENIRONMENT

* Ensure you have perl5.24 or greater (with [plenv](https://github.com/tokuhirom/plenv#installation) if you want an isolated environment)
* Install cpanm: `perl -MCPAN -e 'install App::cpanminus'`
* To install libraries: `cpanm --installdeps .`

You can the decide how to deploy this web application.  See DEPLOYMENT.

If you are looking to extend the game or run the tests, you will need:

* `cpanm --installdeps --with-develop .`
* `npm ci`
    
### DEPLOYMENT

There are several ways to run this web app. 
    
### Run it from the command line for local testing 

* Changed to the directory that contains this file (referred to as $INSTALL_DIR)
* To restrict access to this game strictly to your local machine, run: `perl script/mountain`
* To have other folks on your LAN access the game, run: `perl script/mountain daemon --url http://0.0.0.0:3000` (pick a TCP port amenable to your environment)

     
### Deploying behind a reverse proxy

This is a good option if you want to make this game available to a
wider audience or already have a web app cluster that you wish to
enhance with PB3K.

- Launch the game as described above using the 'daemon --url XXX' invocation.
- If deployed on linux, consider using systemd and making this a service.  (or a launchd service if on mac)
  
      
### Reverse proxy considerations

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

## Development approach

This project was developed with AI-assisted tooling: specialized agents handle
implementation scaffolding, boundary-rule review, and plan analysis, while
human review gates every change through CI (tests, linting, structural checks).
The result is a hybrid workflow — AI accelerates iteration, human judgment
owns architecture and quality.


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
