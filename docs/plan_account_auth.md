# Plan: Account Authentication & Moderation

## Goal

Replace the current zero-auth login (any name = any account) with a
token-gated system that prevents account hijacking while keeping
friction low.

---

## Design

### Architecture

Auth business logic lives in `MagicMountain::Service::Authentication`.
Sessions controller stays thin. Admin endpoints live in
`MagicMountain::Controller::Admin`.

### Token Storage

Existing `password` and `disabled` columns are replaced by:
`token_hash`, `remember_token_hash`, `banned`.

### Wordlist

`content/wordlist.txt` — 10,000+ common English words, one per line.
Loaded at service construction time. If the file is missing, the
service falls back to a built-in list of 256 short words (reduced
entropy but functional for development).

### Collision Check

Skipped. With 10K³ ≈ 1T combinations and < 1K expected accounts,
collision probability is ~10⁻¹³. The cost of verifying uniqueness
against bcrypt hashes is prohibitive (O(n·bcrypt)). Instead, allow
collisions at generation time and handle at login: if two accounts
have the same plaintext token, the first `verify_token` match wins.
This is a ~10⁻¹³ edge case with no security impact.

### Login Flow — API Contract

All interactions go through `POST /sessions` with optional body
fields. No separate `/sessions/verify` endpoint needed.

| Case | Request body | Response body |
|------|-------------|---------------|
| New account | `{ displayName: "alice" }` | `{ ok: 1, token: "crab-shoe-83", show_token: 1, csrf_token, player }` |
| Returning, cookie valid | `{ displayName: "alice" }` + `Cookie: mm_session=...` | `{ ok: 1, csrf_token, player }` (unchanged) |
| Returning, cookie valid but session expired | `{ displayName: "alice" }` + `Cookie: mm_remember=...` | `{ ok: 1, csrf_token, player }` (session refreshed from remember cookie) |
| Returning, no cookie | `{ displayName: "alice" }` | `{ ok: 0, need_token: 1, displayName: "alice" }` |
| Returning, token submitted | `{ displayName: "alice", token: "crab-shoe-83" }` | `{ ok: 1, csrf_token, player }` |

The `show_token` flag and `token` field in the new-account response
tell the client to render the token display. The client shows the
token text, waits for the user to acknowledge, then either continues
to `/game` or provides a "Continue" button.

### JS Impact

The inline `<script>` in `templates/game/show.html.ep` (lines 78–98)
is rewritten to handle all response types:

```javascript
document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = document.getElementById('display-name').value.trim();
  const errEl = document.getElementById('error-msg');
  errEl.style.display = 'none';
  if (!name) return;
  const body = { displayName: name };
  const tokenField = document.getElementById('token-input');  // shown only when need_token
  if (tokenField && tokenField.value) body.token = tokenField.value.trim();
  const resp = await fetch('/sessions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const data = await resp.json();
  if (!data.ok) {
    if (data.need_token) {
      // Replace login form with token prompt
      document.getElementById('login-form').innerHTML = `
        <p>Enter your token for <strong>${data.displayName}</strong></p>
        <input type="text" id="token-input" class="mm-input" placeholder="Your token" required style="width:100%;box-sizing:border-box;margin-bottom:0.5rem">
        <button type="submit" class="mm-btn mm-btn-primary" style="width:100%">Verify</button>
        <p style="font-size:0.7rem;color:var(--mm-text-dim);margin-top:0.5rem">Lost your token? Contact an admin.</p>`;
      return;
    }
    errEl.textContent = data.error || 'Login failed';
    errEl.style.display = 'block';
    return;
  }
  if (data.show_token && data.token) {
    // Show token once, then continue
    const content = document.getElementById('panel-primary');
    content.innerHTML = `
      <div class="mm-panel" style="max-width:24rem;margin:2rem auto;text-align:center">
        <div class="mm-panel-header">ACCOUNT CREATED</div>
        <div class="mm-panel-body">
          <p style="color:var(--mm-text-dim);font-size:0.78rem">Your access token — write this down:</p>
          <p style="font-size:1.4rem;color:var(--mm-amber);letter-spacing:0.15em;margin:1rem 0;font-weight:600">${data.token}</p>
          <p style="font-size:0.72rem;color:var(--mm-red)">You will need this to log in from a new device.</p>
          <button class="mm-btn mm-btn-primary" style="width:100%;margin-top:0.75rem" onclick="window.location.href='/game'">Continue</button>
        </div>
      </div>`;
    return;
  }
  window.location.href = '/game';
});
```

### Remember-Me Cookie

Uses Mojolicious signed cookies with JSON-encoded payload:

```perl
use Mojo::JSON 'encode_json';

# Set on successful login:
my $value = encode_json({
    account_id => $account->getCol('id'),
    token      => $remember_token,
});
$c->cookie(mm_remember => $value, {
    signed   => 1,
    httpOnly => 1,
    secure   => $c->req->is_secure,
    sameSite => 'Lax',
    path     => '/',
});
```

Read on auto-login attempt:
```perl
my $data = eval { decode_json($c->signed_cookie('mm_remember') // '') };
if ($data && $data->{account_id} && $data->{token}) {
    ...
}
```

### Existing Account Migration

`data/accounts.json` contains accounts with no token fields. These
accounts are detected at first login attempt: if `token_hash` is
undef, the service returns `need_admin_reset: 1` with a message
"Account requires admin token reset." The admin uses the
`POST /admin/account/reset-token` endpoint to generate a token for
the account.

For production use, run `perl -Ilib script/mountain migrate-auth`
which assigns tokens to all accounts and prints them. This script
is a one-time utility in `Command/`.

### Route Registration

```
GET /health
Public: /, /login, /logout, DELETE /sessions
$no_maintenance (maintenance check)
  $rate_limited (rate limit check)
    POST /sessions                     # unchanged — no CSRF, no session
    POST /sessions/verify              # new: no CSRF, no session (if kept)
    $admin_bridge (X-Admin-Secret check)
      POST /admin/account/reset-token
      POST /admin/account/ban
      POST /admin/account/unban
    GET /game
    $auth (session auth check)
      GET resources...
      $auth_write (CSRF check)
        POST writes...
```

The `$admin_bridge` is:
```perl
my $admin_bridge = $rate_limited->under('/admin' => sub ($c) {
    my $secret = $c->req->headers->header('X-Admin-Secret') // '';
    return 1 if $c->app->auth_service->admin_authenticate($secret);
    $c->render(json => { ok => 0, error => 'Unauthorized' }, status => 401);
    return undef;
});
```

### Column Schema

Current: `username, password, disabled`
New:     `username, token_hash, remember_token_hash, banned`

The `disabled` column is removed. The `disable_account` command is
updated to set `banned => 1` (and renamed to `ban_account`).

### Service Construction

```perl
# MagicMountain.pm startup:
has auth_service => sub ($self) {
    MagicMountain::Service::Authentication->new(app => $self);
};
```

Matches existing pattern (`shed_manager`, `maintenance`, etc.).

### New CPAN Dependencies

Only `Crypt::Bcrypt`. Random bytes use `Mojo::Util::secure_rand_bytes`
(bundled with Mojolicious) — no `Crypt::URandom` needed.

---

## Changes

### New files

| File | Purpose |
|------|---------|
| `lib/MagicMountain/Service/Authentication.pm` | Token gen/verify, remember-token, admin auth |
| `lib/MagicMountain/Controller/Admin.pm` | Admin endpoints (token reset, ban, unban) |
| `content/wordlist.txt` | 10K+ words for token generation |
| `lib/MagicMountain/Command/ban_account.pm` | CLI ban/unban (replaces disable_account) |

### Modified files

| File | Change |
|------|--------|
| `Model/Account.pm` | Replace `password, disabled` with `token_hash, remember_token_hash, banned`; `create()` sets `banned => 0` |
| `Controller/Sessions.pm` | `create` calls auth service; no inline auth logic |
| `Controller/Admin.pm` | (new) |
| `MagicMountain.pm` | Add `auth_service` attribute, admin bridge, admin routes, warn on default secrets, `defaultConfig` for `bcrypt_cost`, `admin_secret` |
| `templates/game/show.html.ep` | Rewrite inline login `<script>` to handle multi-step flow |
| `magic_mountain.yml` | Add `bcrypt_cost: 10`, `admin_secret: "override-me"` |
| `cpanfile` | Add `Crypt::Bcrypt` |
| `docs/TUNING.md` | Add `bcrypt_cost`, `admin_secret` to config table |
| `bin/walkthrough` | Verify response includes `token` + `show_token` on new account; flow unchanged otherwise |
| `Command/disable_account.pm` | Rename to `ban_account.pm`, use `banned` column |

### Tests

| File | Change |
|------|--------|
| `t/session.t` | Remove pre-created `alice` account subtests (no token_hash); replace with: new account flow (get token), returning with token, wrong token fails, banned rejected, admin reset restores access |
| `t/admin_account.t` | New: token reset, ban, unban with valid/invalid admin secret |

### Removed

| File | Reason |
|------|--------|
| `Command/disable_account.pm` | Replaced by `ban_account.pm` |

---

## Verification

1. `prove -l t/session.t t/admin_account.t`
2. `bash bin/walkthrough`
3. Manual: new account → get token → logout → login with token
4. Manual: wrong token → error; banned → error
5. `make indent && make clean`
6. `make cover && make report`
7. Delete this plan doc after implementation committed
