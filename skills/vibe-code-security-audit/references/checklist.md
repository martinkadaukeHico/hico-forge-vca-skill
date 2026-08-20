# Security Checklist Reference

Concrete things to check per category. "Grep for" patterns are starting points, not exhaustive — adapt to the actual language/framework.

## 1. Authentication

**Password storage**
- Good: bcrypt, argon2, scrypt with reasonable cost factor (bcrypt rounds ≥ 10-12).
- Bad: MD5, SHA1, plain SHA256/SHA512 (no salt/stretching), plaintext.
- Grep for: `md5(`, `sha1(`, `createHash('sha256'` used directly on passwords, `password ==`, `password ===` comparisons against stored value (should use a hash-compare function, not `==`).

**JWT**
- Verify the signature algorithm is explicitly enforced server-side on verify calls (reject `alg: none` and algorithm confusion attacks — e.g. don't accept both RS256 and HS256 if only one is intended).
- Check `exp` claim is set and reasonably short-lived (access tokens: minutes-to-hours, not days/never).
- Refresh tokens: rotated on use, revocable, stored in httpOnly+secure+SameSite cookies — not localStorage/sessionStorage (XSS-readable).
- Grep for: `jwt.verify(`, `jwt.decode(` (decode without verify is a red flag if used for auth decisions), `algorithms:` option missing or overly permissive.

**OAuth**
- `state` parameter generated, stored, and validated on callback (CSRF protection).
- Redirect URI allowlist enforced server-side, not just matched loosely (no open redirect via substring match).
- PKCE used for public/native clients.

**Session management**
- Session ID regenerated on login (fixation protection).
- Cookies: `HttpOnly`, `Secure`, `SameSite=Lax` or `Strict`.
- Logout actually invalidates server-side session/token, not just clears client state.

**Brute force**
- Rate limiting or account lockout on `/login`, `/signup`, `/password-reset`, `/verify-otp` endpoints.
- Grep for: these routes with no rate-limit middleware applied.

**MFA**
- If present, check it's enforceable (not just offered) for sensitive accounts/actions.

## 2. Authorization / User Management — the #1 vibe-coding gap

**IDOR / BOLA (Broken Object Level Authorization)**
This is the single most common and highest-impact vibe-coding vulnerability. Pattern: an endpoint checks "is this user logged in?" but never checks "does this user own/have access to *this specific resource*?"

- For every endpoint that takes an ID (`/api/orders/:id`, `/api/users/:id/documents`, etc.), verify the handler checks `resource.ownerId === req.user.id` (or equivalent role check) before returning/modifying data — not just that a valid session exists.
- Test mentally: "what happens if I change the ID in this request to someone else's ID?"
- Grep for: route handlers with `req.params.id` / path params used directly in a DB query with no ownership filter in the `WHERE` clause or no post-fetch ownership check.

**Privilege escalation**
- Can a user-editable request body set fields like `role`, `isAdmin`, `permissions`? Check update/PATCH endpoints strip these fields server-side rather than trusting client input (mass assignment).
- Grep for: `Object.assign(user, req.body)`, `user.update(req.body)`, `**request.data` unpacked directly into a model without an allowlist.

**Role/permission checks**
- Confirm authorization checks happen server-side in middleware/handler, not only hidden/disabled in frontend UI (e.g. an admin panel route that's just unlinked in the UI but has no server check).

**Account enumeration**
- Login/signup/reset error messages don't reveal whether an email/username exists ("invalid credentials" not "no user with that email").

**Password reset**
- Reset tokens: single-use, expire quickly (e.g. 15-60 min), sufficiently random (not sequential/predictable), and don't leak the user ID/email in a way that lets an attacker guess valid combinations.

## 3. Input Validation / Injection

- SQL/NoSQL: parameterized queries or ORM methods only. Grep for string concatenation/interpolation into queries: `` `SELECT * FROM users WHERE id = ${id}` ``, `"... " + userInput`.
- XSS: output encoding on any user-controlled content rendered in HTML; check for `dangerouslySetInnerHTML`, `innerHTML =`, `v-html` used with unsanitized input. CSP header present.
- Command injection: any `exec(`, `child_process.exec(`, `os.system(` with user input concatenated in.
- File uploads: type/extension validated server-side (not just client-side/by MIME type header, which is spoofable), size limits enforced, uploaded files not served from a path that allows path traversal (`../`), no execution of uploaded files.

## 4. API Security

- CORS: not `Access-Control-Allow-Origin: *` combined with `Access-Control-Allow-Credentials: true`. Origin allowlist, not wildcard, when credentials are involved.
- Deny-by-default: new routes require auth middleware explicitly, rather than auth being opt-in per route (easy to forget one).
- Mass assignment (see above, also applies broadly to any API accepting JSON bodies).
- Production error responses don't leak stack traces, internal file paths, or DB error messages.

## 5. Secrets & Configuration

- No hardcoded API keys, DB passwords, JWT signing secrets in source. Grep for: `sk_live_`, `AKIA`, `password =`, `SECRET =`, `apiKey:` followed by a literal string.
- `.env` / secret files present in `.gitignore`; check git history too if possible (`git log -p -- .env`) since a since-removed committed secret is still compromised and needs rotating.
- Debug/verbose mode disabled in production config.
- JWT signing secret is long/random, not a placeholder like `"secret"` or `"changeme"`.

## 6. Data Protection

- TLS enforced; HSTS header present.
- Sensitive PII encrypted at rest where the data sensitivity warrants it.
- DB credentials used by the app follow least privilege (not a superuser/root DB account).

## 7. Dependencies & Infra

- Run the ecosystem's audit tool if available: `npm audit`, `pip-audit`, `cargo audit`, etc.
- Flag major frameworks on versions with known CVEs.
- Security headers present: `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options: nosniff`.

## 8. Logging & Monitoring

- Auth failures, privilege changes, and access to sensitive resources are logged.
- Logs do not contain passwords, tokens, full card numbers, or other secrets in plaintext.
