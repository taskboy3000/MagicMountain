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

has max_attempts          => 5;
has max_attempts_per_name => 5;
has window_minutes        => 15;
has block_minutes         => 15;

my %attempts;
my %attempts_by_name;

sub time_func ($self) { time }

sub check ($self, $ip) {
    my $entry = $attempts{$ip} or return 1;

    my $now = $self->time_func;

    # Currently blocked and block hasn't expired yet
    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    # Block expired? Clean up and allow
    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $attempts{$ip};
        return 1;
    }

    # Window expired? Reset
    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        delete $attempts{$ip};
        return 1;
    }

    return 1;
}

sub record_failure ($self, $ip) {
    my $now = $self->time_func;
    my $entry = $attempts{$ip} //= { count => 0, first_attempt => $now };

    # If currently blocked, don't modify state — just return
    if (defined $entry->{blocked_until} && $now < $entry->{blocked_until}) {
        return $entry->{count};
    }

    # Block expired? Clear it so failures start fresh
    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $entry->{blocked_until};
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }

    # Window expired? Reset
    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
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

sub check_name ($self, $name) {
    my $entry = $attempts_by_name{$name} or return 1;
    my $now = $self->time_func;
    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $attempts_by_name{$name};
        return 1;
    }
    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        delete $attempts_by_name{$name};
        return 1;
    }
    return 1;
}

sub record_name_failure ($self, $name) {
    my $now = $self->time_func;
    my $entry = $attempts_by_name{$name} //= { count => 0, first_attempt => $now };
    return $entry->{count} if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    if (defined $entry->{blocked_until} && $now >= $entry->{blocked_until}) {
        delete $entry->{blocked_until};
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }
    if ($now - $entry->{first_attempt} > $self->window_minutes * 60) {
        $entry->{count} = 0;
        $entry->{first_attempt} = $now;
    }
    $entry->{count}++;
    $entry->{blocked_until} = $now + ($self->block_minutes * 60) if $entry->{count} >= $self->max_attempts_per_name;
    return $entry->{count};
}

sub record_name_success ($self, $name) {
    delete $attempts_by_name{$name};
}

sub get_remaining ($self, $ip) {
    my $entry = $attempts{$ip} or return $self->max_attempts;
    my $now = $self->time_func;

    # If blocked, 0 remaining
    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};

    # Window expired? Full allowance
    return $self->max_attempts if $now - $entry->{first_attempt} > $self->window_minutes * 60;

    return $self->max_attempts - $entry->{count};
}

sub get_reset_time ($self, $ip) {
    my $entry = $attempts{$ip} or return 0;
    my $now = $self->time_func;

    if (defined $entry->{blocked_until} && $now < $entry->{blocked_until}) {
        return $entry->{blocked_until} - $now;
    }

    my $window_end = $entry->{first_attempt} + ($self->window_minutes * 60);
    return $window_end > $now ? $window_end - $now : 0;
}

sub get_name_remaining ($self, $name) {
    return $self->max_attempts_per_name unless my $entry = $attempts_by_name{$name};
    my $now = $self->time_func;
    return 0 if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    return $self->max_attempts_per_name if $now - $entry->{first_attempt} > $self->window_minutes * 60;
    return $self->max_attempts_per_name - $entry->{count};
}

sub get_name_reset_time ($self, $name) {
    my $entry = $attempts_by_name{$name} or return 0;
    my $now = $self->time_func;
    return $entry->{blocked_until} - $now if defined $entry->{blocked_until} && $now < $entry->{blocked_until};
    my $window_end = $entry->{first_attempt} + ($self->window_minutes * 60);
    return $window_end > $now ? $window_end - $now : 0;
}

sub cleanup ($self) {
    my $now = $self->time_func;
    for my $ip (keys %attempts) {
        my $e = $attempts{$ip};
        if (defined $e->{blocked_until} && $now >= $e->{blocked_until}) {
            delete $attempts{$ip};
        }
        elsif (!$e->{blocked_until} && $now - $e->{first_attempt} > $self->window_minutes * 60) {
            delete $attempts{$ip};
        }
    }
    for my $name (keys %attempts_by_name) {
        my $e = $attempts_by_name{$name};
        if (defined $e->{blocked_until} && $now >= $e->{blocked_until}) {
            delete $attempts_by_name{$name};
        }
        elsif (!$e->{blocked_until} && $now - $e->{first_attempt} > $self->window_minutes * 60) {
            delete $attempts_by_name{$name};
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

The rate limiter bridge — includes `Retry-After` and `X-RateLimit-*` headers:

```perl
my $rate_limited = $no_maintenance->under('/' => sub ($c) {
    my $ip = $c->tx->remote_address;
    $ip = ($c->req->headers->header('X-Forwarded-For') // '') =~ /([^,\s]+)/
        ? $1 : $ip
        if $c->app->config->{rate_limit_trusted_proxies};

    my $rl = $c->app->rate_limiter;

    unless ($rl->check($ip)) {
        my $retry_after = $rl->get_reset_time($ip);
        $c->res->headers->header('Retry-After' => $retry_after);
        $c->render(json => {
            ok => 0,
            error => 'Too many attempts',
            retry_after => $retry_after,
        }, status => 429);
        return undef;
    }

    # Add rate limit info headers on every request
    $c->res->headers->header('X-RateLimit-Limit'     => $rl->max_attempts);
    $c->res->headers->header('X-RateLimit-Remaining'  => $rl->get_remaining($ip));
    $c->res->headers->header('X-RateLimit-Reset'      => $rl->get_reset_time($ip));

    return 1;
});
$rate_limited->post('/sessions')->to('sessions#create')->name('login');
```

### Controller changes (`Sessions::create`)

The controller records outcomes for **both** IP-based and account-name-based
tracking. Account-name limiting is checked in the controller (not the bridge)
because the name comes from the request body:

```perl
sub create ($self) {
    my $ip   = $self->tx->remote_address;
    my $name = ($self->req->json->{displayName} // '');
    my $rl   = $self->app->rate_limiter;

    # Account-name rate limit check (separate from IP check in bridge)
    if ($name && !$rl->check_name(lc $name)) {
        my $retry_after = $rl->get_name_reset_time(lc $name);
        $self->res->headers->header('Retry-After' => $retry_after);
        return $self->render(json => {
            ok => 0, error => 'Too many attempts for this account',
            retry_after => $retry_after,
        }, status => 429);
    }

    # ... existing name validation, disabled check, account lookup, create ...

    if ($some_error_condition) {
        $rl->record_failure($ip);
        $rl->record_name_failure(lc $name) if $name;
        return $self->render(json => { ok => 0, error => '...' }, status => 4xx);
    }

    $rl->record_success($ip);
    $rl->record_name_success(lc $name) if $name;
    $self->render(json => { ok => 1, ... });
}
```

Names are lowercased before keying to prevent case-variation attacks.

The bridge's IP `check` call happens *before* the controller runs. If the IP
is already blocked, the bridge returns 429 and the controller never executes.
The account-name check runs in the controller, after the bridge allows the
request through, because the name is only known once the request body is
parsed.

### App helper + config (`MagicMountain.pm`)

```perl
# In defaultConfig:
rate_limit_max_attempts         => 5,
rate_limit_max_attempts_per_name => 5,
rate_limit_window_minutes       => 15,
rate_limit_block_minutes        => 15,
rate_limit_cleanup_interval     => 300,
rate_limit_trusted_proxies      => 0,

# Helper:
has rate_limiter => sub ($self) {
    MagicMountain::RateLimiter->new(
        max_attempts          => $self->config->{rate_limit_max_attempts},
        max_attempts_per_name => $self->config->{rate_limit_max_attempts_per_name},
        window_minutes        => $self->config->{rate_limit_window_minutes},
        block_minutes         => $self->config->{rate_limit_block_minutes},
    );
};
```

### Cleanup timer in app startup (`MagicMountain.pm::startup`)

Periodic cleanup prevents unbounded memory growth under attack:

```perl
my $interval = $self->config->{rate_limit_cleanup_interval};
Mojo::IOLoop->recurring($interval => sub {
    $self->rate_limiter->cleanup;
}) if $interval;
```

### Config (`magic_mountain.yml`)

```yaml
rate_limit_max_attempts: 5
rate_limit_max_attempts_per_name: 5
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
| Key (IP) | IP address | Prevents broad spraying |
| Key (account name) | Normalized lowercase name | Prevents targeted attacks on known accounts from multiple IPs |
| Window | Rolling window from first attempt | Tied to first attempt per burst, not calendar boundaries. Resets after `window_minutes` of inactivity |
| Block precedence | Block checked before window | Prevents block bypass when window expires during a block |
| Bridge placement | After maintenance gate | Rate-limiting should not bypass maintenance mode |
| Controller records outcome | After bridge pass | Bridge tracks blocked state; controller tracks consumed attempts |
| Headers | `Retry-After` + `X-RateLimit-*` | Standard rate limiting headers for client awareness |
| Cleanup | Periodic timer via `IOLoop->recurring` | Prevents unbounded memory growth |

---

## Multi-Worker Limitation

The in-memory `%attempts` hash is per-process. With multiple prefork workers,
each worker maintains its own counter. An attacker making `max_attempts × N`
requests (where N = number of workers) can exhaust all workers' allowances
before any single worker blocks them. This is acceptable for alpha, but a
shared backend (Redis, shared memory, or database) should be added before
production deployment.

---

## Tests (`t/rate_limiter.t`)

### Unit tests (RateLimiter class)

1. **Allow first request**: `check('1.2.3.4')` returns true before any failures
2. **Count increments**: `record_failure` returns 1, 2, 3, ... on successive calls
3. **Block at threshold**: `record_failure` called N times, `check` returns false after Nth
4. **Unblock after timeout**: Advance time beyond `block_minutes`, verify `check` returns true
5. **Window reset on inactivity**: Failures within window accumulate; after window expiry, counter resets
6. **Success clears**: `record_success` deletes entry, `check` returns true
7. **Cleanup removes stale**: Expired entries (both blocked and unblocked) removed by `cleanup`
8. **Cleanup leaves active**: Non-expired entries survive `cleanup`
9. **IP isolation**: Failures for one IP don't affect another IP
10. **Block not bypassed by window expiry**: Set block, advance time past window but before block expiry — check still returns false
11. **Retry-After calculation**: `get_reset_time` returns positive seconds when blocked
12. **X-RateLimit-Remaining correct**: `get_remaining` decrements correctly with failures
13. **Name-based blocking**: `check_name('foo')` returns false after max failures per name
14. **Name isolation**: Failures for one name don't affect another name
15. **Case normalization**: `check_name('Alice')` matches `check_name('alice')`

### Integration tests (Mojo app)

1. **N+1 requests block**: Send N+1 POST requests to `/sessions`, last returns 429
2. **Blocked gets error JSON**: Verify `{ ok => 0, error => 'Too many attempts' }`
3. **Blocked gets Retry-After**: Verify `Retry-After` header on 429 response
4. **Rate limit headers present**: Verify `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` on all responses
5. **Different IPs independent**: Simulate requests from different remote addresses, verify independent counting
6. **Successful login resets**: Fire failures, then succeed, verify next request allowed
7. **`X-Forwarded-For` header**: With `rate_limit_trusted_proxies` enabled, verify header value used for IP
8. **Name-based blocking in controller**: POST to `/sessions` with the same displayName > N times, last returns 429 with account-name error
9. **Name blocking independent of IP**: Same name from different IPs still triggers name block
10. **Different names independent**: Failures for one name don't affect another name
11. **Case-insensitive name keying**: `displayName=Alice` and `displayName=alice` share the same counter

### Test harness notes

- Use `$c->tx->remote_address` — in `Test::Mojo`, set via
  `$t->ua->server->app->hook(after_build_tx => sub { shift->remote_address('1.2.3.4') })`
- For time-dependent tests, inject fake time via `time_func` method:
  `$rl->time_func = sub { ... }` or use `Test::Time`
- Mock `rate_limit_max_attempts` to a low value (e.g., 2) for fast tests

---

## Files

| File | Action |
|------|--------|
| `lib/MagicMountain/RateLimiter.pm` | Create — rate limiter class |
| `lib/MagicMountain.pm` | Add `rate_limiter` helper, `$rate_limited` bridge in `buildRoutes`, defaults in `defaultConfig`, cleanup timer in `startup` |
| `lib/MagicMountain/Controller/Sessions.pm` | Add `record_failure`/`record_success` calls to `create` |
| `magic_mountain.yml` | Add rate limit config values |
| `t/rate_limiter.t` | Create — unit + integration tests |

---

## Open Questions

1. **Multi-worker state** (discussed above): In-memory `%attempts` is
   per-process. Acceptable for alpha, but needs a shared backend before
   production. This is documented as a known limitation — no action needed
   now.
