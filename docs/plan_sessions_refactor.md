# Plan: Sessions Controller Refactor

## Problem

`Sessions.pm:create` calls `_build_session` from **4 separate branches** (remember-me,
new account, test-mode legacy, token verify). Each call site repeats the same
`or return; return $self->render(json => $result)` pattern, and the new-account
branch adds `mm_new_credentials` / `show_credentials` as a special case.

Additionally, most branches call `_set_remember_cookie` with a pre-built token
before calling `_build_session`. But `_build_session` unconditionally generates
a *new* remember token and calls `_set_remember_cookie` at its end (line 265),
overwriting the branch-level cookie. Those branch-level calls are dead code.

Same pattern exists in `recover`: calls `_set_remember_cookie` (line 184), then
`_build_session` overwrites it (line 265).

---

## Solution

### 1. Extract `_resolve_remember_me`

Pull the remember-me cookie check into a private method:

```perl
sub _resolve_remember_me ($self, $name, $auth) {
    my $data = $self->_read_remember_cookie or return;
    my $acct = $self->app->accounts->get($data->{account_id}) or return;
    return unless $acct->getCol('username') eq $name;
    return if $acct->getCol('banned');
    return unless $auth->verify_remember_token($acct, $data->{token});
    return $acct;
}
```

This moves ~12 lines of inline conditional logic into a single-call helper.

### 2. Restructure `create` to a single `_build_session` call

The new flow:

```
1. Validation + rate limiting (unchanged)
2. Early return: existing session cookie matches (unchanged)
3. Resolve account into $account, track $auto_authenticated and $creds:
   a. Try remember-me → if success, $auto_authenticated = 1
   b. Find or create account:
      - If account doesn't exist: create, $auto_authenticated = 1, $creds = { ... }
      - If account exists and banned: return 403
      - If account exists and no token_hash:
        test mode → auto-generate token, $auto_authenticated = 1
        otherwise → return need_admin_reset
      - If token submitted: verify, return 403 on error, $auto_authenticated = 1
      - elsif !$auto_authenticated: return need_token
4. Single _build_session call (with or return)
5. Single render (with mm_new_credentials if applicable)
```

The `$auto_authenticated` flag is the critical addition. It distinguishes
paths that don't need a token submission (remember-me, new account, test-mode
auto-generate, successful token verify) from paths where the user hasn't
provided one yet.

**Key changes:**
- All four `_build_session` call sites become one.
- No `_set_remember_cookie` calls in `create` — `_build_session` handles it.
- No duplicate `->record_success` / `->record_name_success` calls — `_build_session` doesn't do rate-limit recording, so callers still do it before `_build_session`.
- The `mm_new_credentials` / `show_credentials` attachment happens once, after `_build_session`.

### 3. Remove redundant `_set_remember_cookie` from `recover`

`recover` line 184 (`$self->_set_remember_cookie(...)`) is overwritten by
`_build_session` line 265. Remove it.

### 4. `_build_session` stays unchanged

No changes to session creation, audit log, remember-cookie refresh, or the
existing bot check / cap check logic.

---

## Files changed

| File | Change |
|------|--------|
| `lib/MagicMountain/Controller/Sessions.pm` | Restructure `create`, extract `_resolve_remember_me`, remove dead `_set_remember_cookie` from `recover` |

---

## Edge cases

| Case | Behavior |
|------|----------|
| New account | Gets session + credentials — same as before |
| Remember-me re-auth | Gets session — same as before |
| Token verify | Gets session — same as before |
| Test-mode legacy account | Gets session — same as before |
| Recovery | Gets session + new credentials — same as before |
| Cap hit / bot check | Returns error, no session — same as before |
| Remember cookie | Set exactly once per login (by `_build_session`) — no longer redundantly set before it |

---

## Tests

Existing tests in `t/session.t`, `t/login.t`, `t/session_fragment.t`, `t/session_cap.t`
already exercise every login path:

| Path | Test |
|------|------|
| New account + credentials | `login.t:57-73`, `session.t:45-64` |
| Remember-me re-auth | `session.t:232-249` |
| Token verify (correct + wrong) | `session.t:66-86` |
| Recovery | `session.t:171-224`, `session_fragment.t:69-84` |
| Session cap | `session_cap.t:6` subtests |
| Banned account | `session.t:147-169`, `login.t:75-84` |
| New-account `show_credentials` | `session_fragment.t:48-67` |

No new tests needed — this is a pure refactor with no behavioral change.
Run `prove t/session_cap.t t/session.t t/login.t t/session_fragment.t` to
confirm existing tests catch any regression.
