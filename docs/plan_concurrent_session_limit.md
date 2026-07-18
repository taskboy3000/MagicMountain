# Plan: Concurrent Session Limit

## Goal

Reject new logins when the number of active (non-expired) sessions reaches a
configurable maximum. Existing sessions are unaffected — only brand-new unique
players are denied.

---

## 1. Config changes

### New key — `max_concurrent_sessions`

Add to `defaultConfig` in `MagicMountain.pm`:

```perl
max_concurrent_sessions => 10,
```

Override in `magic_mountain.yml`. Set to `0` for unlimited.

### Existing key — `session_timeout_minutes` default change

Change default from `60` to `30` in `defaultConfig`.

### Update `magic_mountain.yml` override

`magic_mountain.yml` currently has `session_timeout_minutes: 60`.

### Update stale fallbacks

| Location | Current | New |
|----------|---------|-----|
| `MagicMountain.pm` (`current_player`) | `// 60` | `// 30` |
| `list_accounts.pm` | `// 60` | `// 30` |

---

## 2. Throttle `touch` in `current_player`

`current_player` already calls `$session->touch` on every request. Add a
**10-second write throttle**:

```perl
my $last = $session->getCol('last_active') // 0;
$session->touch if time - $last >= 10;
```

---

## 3. Model boundary — `Session.pm` gains `active_count`

```perl
sub active_count ($self, $timeout_minutes) {
    $self->load;
    my $cutoff = time - $timeout_minutes * 60;
    my $expired = $self->find(sub { ($_[0]->{last_active} // 0) < $cutoff });
    for my $s (@$expired) { $self->delete($s->getCol('id')); }
    my $active = $self->find(sub { ($_[0]->{last_active} // 0) >= $cutoff });
    return scalar @$active;
}
```

Uses `find` + `delete` — the standard model API.

---

## 4. Cap check — refactor `_build_session` return pattern

`_build_session` returns `undef` on error (bot check or cap hit). Callers use
`or return` and only render if result is a hashref.

### Logic

```perl
sub _build_session ($self, $account, $ip, @rest) {
    my $player_id = $account->getCol('id');

    # Bot check — render 403, return undef
    ...
    if ($bot_char) { $self->render(json => ..., status => 403); return; }

    # Cap check — render 503, return undef
    my $max = $self->app->config->{max_concurrent_sessions} // 10;
    if ($max > 0) {
        ...
        if ($active >= $max) {
            $self->render(json => { ok => 0, error => '...' }, status => 503);
            return;
        }
    }

    # Session creation (unchanged) ...
    return { ok => 1, csrf_token => ..., player => { ... } };
}
```

### Callers updated

```perl
# Before:  return $self->render(json => $self->_build_session(...));
# After:   my $result = $self->_build_session(...) or return;
#          return $self->render(json => $result);
```

Five call sites: remember-me, new account, token verify (2x), recovery.

---

## 5. Files changed

| File | Change |
|------|--------|
| `MagicMountain.pm` | `session_timeout_minutes` default: `60` → `30` |
| `MagicMountain.pm` | Add `max_concurrent_sessions => 10` |
| `MagicMountain.pm` | `current_player` `// 60` → `// 30`, add 10s throttle |
| `Model/Session.pm` | Add `active_count($timeout_minutes)` |
| `Controller/Sessions.pm` | Refactor `_build_session` return; update 5 callers |
| `Command/list_accounts.pm` | `// 60` → `// 30` |
| `magic_mountain.yml` | `session_timeout_minutes: 60` → `30` |
| `docs/TUNING.md` | Add `max_concurrent_sessions`; update default |

---

## 6. Tests

`t/session_cap.t` — 6 subtests, 105 assertions:
- Cap of 10 blocks 11th, allows 10
- Cap of 0 is unlimited (15 players)
- Cap of 1 blocks second player
- Same player reconnecting bypasses cap
- Expired session purged, slot freed
- Error response shape: `{ ok: 0, error: '...' }` status 503
