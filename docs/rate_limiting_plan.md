# Rate Limiting — Implementation Plan

**Priority**: P0 (before real users)
**Status**: Not started

## Motivation

The login endpoint (`POST /sessions`) has no brute-force protection. Since
accounts are auto-created on first login (name-only auth), an attacker can:

- Enumerate existing usernames (response differentiates new vs returning)
- Flood the session store with bogus sessions
- Rapidly cycle account creation/deletion

Rate limiting is the only defense until password auth is added.

---

## Approach

In-memory IP-based rate limiter implemented as a Mojo `under` bridge between
the maintenance gate and the login route. Clean, self-contained, zero new CPAN
dependencies. No persistent storage — state resets on server restart, which is
acceptable for alpha.

---

## Design

### RateLimiter class (`lib/MagicMountain/RateLimiter.pm`)

```perl
package MagicMountain::RateLimiter;
use Mojo::Base '-base', '-signatures';

has max_attempts      => 5;
has window_minutes    => 15;
has block_minutes     => 15;

my %attempts;

sub check ($self, $ip) {
    my $entry = $attempts{$ip} or return 1;

    # Clean expired entries lazily
    if (defined $entry->{blocked_until} && time >= $entry->{blocked_until}) {
        delete $attempts{$ip};
        return 1;
    }

    # Window expired? Reset
    if (time - $entry->{first_attempt} > $self->window_minutes * 60) {
        delete $attempts{$ip};
        return 1;
    }

    # Currently blocked
    return 0 if $entry->{blocked_until};

    return 1;
}

sub record_failure ($self, $ip) {
    my $now = time;
    my $entry = $attempts{$ip} //= { count => 0, first_attempt => $now };

    # Reset window if expired
    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
        delete $entry->{blocked_until};
    }

    $entry->{count}++;

    if ($entry->{count} >= $self->max_attempts) {
        $entry->{blocked_until} = $now + ($self->block_minutes * 60);
    }

    return $entry->{count};
}

sub record_success ($self, $ip) {
    delete $attempts{$ip};
}

sub cleanup ($self) {
    my $now = time;
    for my $ip (keys %attempts) {
        my $e = $attempts{$ip};
        if ($e->{blocked_until} && $now >= $e->{blocked_until}) {
            delete $attempts{$ip};
        } elsif (!$e->{blocked_until} && $now - $e->{first_attempt} > $self->window_minutes * 60) {
            delete $attempts{$ip};
        }
    }
}
```

### Route integration (`MagicMountain.pm::buildRoutes`)

The current route structure:

```
$r->get('/login')                        # login form (public)
$r->get('/logout')                       # logout (public)
$r->delete('/sessions')                  # logout API (public)

$no_maintenance (bridge: 503 if maintenance)
  └── $no_maintenance->post('/sessions') # login action

$auth (bridge: redirect if not logged in)
  └── authenticated routes
```

Target structure:

```
$r->get('/login')
$r->get('/logout')
$r->delete('/sessions')

$no_maintenance (bridge: 503 if maintenance)
  └── $rate_limited (bridge: 429 if rate-limited)     ← NEW
        └── $rate_limited->post('/sessions')

$auth (bridge: redirect if not logged in)
  └── authenticated routes
```

The rate limiter bridge:

```perl
my $rate_limited = $no_maintenance->under('/' => sub ($c) {
    my $ip = $c->tx->remote_address;
    $ip = ($c->req->headers->header('X-Forwarded-For') // '') =~ /([^,\s]+)/
        ? $1 : $ip
        if $c->app->config->{rate_limit_trusted_proxies};

    unless ($c->app->rate_limiter->check($ip)) {
        $c->render(json => { ok => 0, error => 'Too many attempts' }, status => 429);
        return undef;
    }
    return 1;
});
$rate_limited->post('/sessions')->to('sessions#create')->name('login');
```

### Controller changes (`Sessions::create`)

The controller records the outcome so the rate limiter can track failures:

```perl
sub create ($self) {
    my $ip = $self->tx->remote_address;
    # ... existing logic ...

    return $self->render(json => { ok => 0, error => 'displayName is required' }, status => 400)
        unless $name;

    # ... name validation, disabled check, account lookup, create ...

    if ($some_error_condition) {
        $self->app->rate_limiter->record_failure($ip);
        return $self->render(json => { ok => 0, error => '...' }, status => 4xx);
    }

    $self->app->rate_limiter->record_success($ip);
    $self->render(json => { ok => 1, ... });
}
```

The bridge's `check` call happens *before* the controller runs. If the IP is
already blocked, the bridge returns 429 and the controller never executes.
The controller records success/failure only after the bridge allows it
through — so `record_failure` is only called when the request actually reaches
the handler, meaning the IP had available attempts and then wasted one.

### App helper + config (`MagicMountain.pm`)

```perl
# In defaultConfig:
rate_limit_max_attempts     => 5,
rate_limit_window_minutes   => 15,
rate_limit_block_minutes    => 15,
rate_limit_cleanup_interval => 300,
rate_limit_trusted_proxies  => 0,

# Helper:
has rate_limiter => sub ($self) {
    MagicMountain::RateLimiter->new(
        max_attempts   => $self->config->{rate_limit_max_attempts},
        window_minutes => $self->config->{rate_limit_window_minutes},
        block_minutes  => $self->config->{rate_limit_block_minutes},
    );
};
```

### Config (`magic_mountain.yml`)

```yaml
rate_limit_max_attempts: 5
rate_limit_window_minutes: 15
rate_limit_block_minutes: 15
rate_limit_cleanup_interval: 300
rate_limit_trusted_proxies: 0
```

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage | In-memory hash | Zero dependencies, fast, acceptable to reset on restart for alpha |
| Key | IP address | Simple, prevents spraying. Account-name keying added later if needed |
| Window | Fixed window from first attempt | Simpler than sliding window; resets after `window_minutes` of inactivity |
| Bridge placement | After maintenance gate | Rate-limiting should not bypass maintenance mode |
| Controller records outcome | After bridge pass | Bridge tracks blocked state; controller tracks consumed attempts |
| Error response | 429 with JSON body | Consistent with API style. `Retry-After` header considered but not critical |

---

## Tests (`t/rate_limiter.t`)

### Unit tests (RateLimiter class)

1. **Allow first request**: `check('1.2.3.4')` returns true before any failures
2. **Count increments**: `record_failure` returns 1, 2, 3, ... on successive calls
3. **Block at threshold**: `record_failure` called N times, `check` returns false after Nth
4. **Unblock after timeout**: Simulate time passing beyond `block_minutes`, verify `check` returns true
5. **Window reset on inactivity**: Failures within window accumulate; after window expiry, counter resets
6. **Success clears**: `record_success` deletes entry, `check` returns true
7. **Cleanup removes stale**: Expired entries (both blocked and unblocked) removed by `cleanup`
8. **Cleanup leaves active**: Non-expired entries survive `cleanup`
9. **IP isolation**: Failures for one IP don't affect another IP

### Integration tests (Mojo app)

1. **N+1 requests block**: Send N+1 POST requests to `/sessions`, last returns 429
2. **Blocked get error JSON**: Verify `{ ok => 0, error => 'Too many attempts' }`
3. **Different IPs independent**: Simulate requests from different remote addresses, verify independent counting
4. **Successful login resets**: Fire failures, then succeed, verify next request allowed
5. **`X-Forwarded-For` header**: With `rate_limit_trusted_proxies` enabled, verify header value used for IP

### Test harness notes

- Use `$c->tx->remote_address` — in `Test::Mojo`, set via `$t->ua->server->app->hook(after_build_tx => sub { shift->remote_address('1.2.3.4') })`
- For time-dependent tests, inject a fake time function into RateLimiter (or use `Test::Time` / `Time::Fake`)
- Mock `rate_limit_max_attempts` to a low value (e.g., 2) for fast tests

---

## Files

| File | Action |
|------|--------|
| `lib/MagicMountain/RateLimiter.pm` | Create — rate limiter class |
| `lib/MagicMountain.pm` | Add `rate_limiter` helper, `$rate_limited` bridge in `buildRoutes`, defaults in `defaultConfig` |
| `lib/MagicMountain/Controller/Sessions.pm` | Add `record_failure`/`record_success` calls to `create` |
| `magic_mountain.yml` | Add rate limit config values |
| `t/rate_limiter.t` | Create — unit + integration tests |

---

## Open Questions

1. **Should account-name rate limiting be added now?** IP-based alone prevents
   broad spraying. Account-name keying would prevent targeted attacks on a
   known username from multiple IPs, but requires persistent storage (or a
   separate in-memory hash). Defer until password auth exists.

2. **Should we add `Retry-After` header to the 429 response?** Standard
   practice but not critical for alpha JS client. Easy to add later.

3. **Should the rate limiter cover other routes?** Currently only login is
   unauthenticated and vulnerable. Authenticated routes are CSRF-protected.
   Other public routes (`GET /login`, `GET /logout`, `DELETE /sessions`) are
   read-only or idempotent.

4. **Should rate limiting be extended to the CLI (`create-account`, etc.)?**
   CLI commands run locally with direct filesystem access — rate limiting
   at the CLI level adds no value.
