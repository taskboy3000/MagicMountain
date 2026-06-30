I am not going to rip you. For your threat model, this is basically passwordless account-by-secret-token, and that is reasonable for a tiny hobby game with no email, no payments, no private user data, and no privileged user roles.

I would tighten a few things:

1. Never store tokens in plaintext. Store only hashes of login/recovery tokens. Treat them exactly like passwords internally.
2. Recovery token should be one-time use. When used, rotate both login token and recovery token.
3. Cookie should be HttpOnly, Secure, and SameSite=Lax or Strict. Thirty days is fine for this use case.
4. Do not put tokens in URLs. Use POST bodies only. URLs leak into logs, browser history, referers, and screenshots.
5. Rate-limit login/create/recovery attempts. Especially by IP and account name. Your friends are jerks; bots are worse.
6. Make account names boringly constrained. Lowercase, limited length, safe characters only. No HTML, no whitespace tricks, no path-like values.
7. Use high-entropy tokens. At least 128 bits random, preferably 192–256 bits, encoded as base64url or hex.
8. Admin reset should also rotate both tokens and print them once. Do not email stored tokens because there should be no stored plaintext token.

The biggest conceptual warning:

The login token is a password. The recovery token is a backup password.

That is fine. Just treat them with password hygiene.

I actually like the design because it matches the game’s scale and avoids collecting personal data. The worst likely failure is someone loses access to a toy game account or a friend logs in as another friend. That is annoying, not catastrophic.

So my verdict: acceptable design, provided tokens are hashed, cookies are hardened, recovery is one-time, and login/recovery endpoints are rate-limited.
