# Reading a security audit for a VCA

The `vibe-code-security-audit` skill audits a conventional SaaS app. A VCA is not
one, and the difference is not cosmetic — **on the first category the generic
checklist gives exactly the wrong answer.** This file is how to apply it anyway.

Run the audit. Then read its findings through this table before acting on any of
them.

---

## The trap, stated plainly

The checklist's §1 (Authentication) and parts of §2 describe what *good* password
hashing, JWT verification, OAuth `state` handling, session fixation protection
and MFA look like. A VCA must contain **none of those things** (§1 rule 7).

So if an audit of a VCA reports "passwords hashed with SHA256 — use bcrypt", the
correct fix is **not** bcrypt. It is deleting the password code, because the app
should not have users, passwords, or a login screen at all.

A citizen developer following the generic advice in good faith will build a
competent login system and get the app rejected at registration. **Finding
authentication code in a VCA is a compliance failure, and the fix is removal.**

State it that way in the report. Do not write "consider using bcrypt" and leave
them to work out that the whole file should go.

---

## Category by category

| Audit category | In a VCA |
|---|---|
| **§1 Password storage, JWT, OAuth, sessions, MFA** | **Forbidden, not "do it well".** Any hit is a CRITICAL compliance finding. Fix = delete. See below for the one real secret a VCA does hold. |
| **§2 IDOR / BOLA** | Reframed — see "The BOLA analogue" below. The generic form (`resource.ownerId === req.user.id`) is impossible: there is no `req.user`. |
| **§2 Mass assignment** | **Applies unchanged.** `PATCH` handlers that splat a request body into a model are as dangerous here as anywhere. |
| **§2 Account enumeration, password reset** | Not applicable. No accounts exist. If either appears, that is §1's finding again. |
| **§3 Injection (SQL, XSS, command), file uploads** | **Applies unchanged, and matters more** — see "Every endpoint is public". |
| **§4 CORS, error leakage** | **Applies unchanged.** Verbose tracebacks are worse here because the app holds a Vault key. |
| **§4 Deny-by-default routes** | Reframed — there is no auth middleware to forget. See below. |
| **§5 Secrets in source, .gitignore, git history** | **Applies, and overlaps the VCA rules.** Plus VCA-specific items below. |
| **§6 TLS, HSTS** | Mostly the platform's job (Forge ingress terminates TLS). Do not add your own TLS handling. |
| **§6 Least privilege on DB / external credentials** | **Applies** — but it is the *admin* who enters those values in Vault. Say so in the report so the finding reaches the person who can act on it. |
| **§7 Dependency CVEs, security headers** | **Applies, and the VCA rules do not cover it at all.** This is a real gap the audit fills — run the ecosystem audit tool. |
| **§8 Logging** | **Applies, plus a hard VCA rule:** never log the Vault API key or any resolved value. |

---

## Every endpoint is public — the reframing that matters most

A conventional app asks "is this route behind auth middleware?". A VCA has **no
app-level authentication at all**, by design. There is nothing to forget to
apply, because there is nothing to apply.

The consequence is the thing to get across: **every endpoint the app exposes is
reachable by anyone who can reach the container.** Protection is the platform's
network boundary, not the app's code.

So the questions worth asking are different:

- Does any endpoint do something destructive that a stray request should not be
  able to trigger? A `POST /api/commit` that writes to a live system is one
  request away from anyone on the network.
- Is there a debug or admin endpoint that exists "just for testing"? It is not
  protected. Nothing is.
- Does an endpoint echo back a resolved secret? `/api/vault/status` must report
  *states and key names only*, never values (§8).

For a citizen developer the useful sentence is: *"assume anyone inside the
company network can call every URL your app answers on, and check that nothing
answers with more than you would put on a poster."*

---

## The BOLA analogue

Generic BOLA is "user A reads user B's order because the handler never checked
ownership". A VCA has no users, so that exact bug cannot exist. The equivalent —
and it is the single most likely serious flaw in a VCA — is:

> **Can the app act on something outside what the manifest declared and the
> admin granted?**

Concretely:

- A ticket-writing app that can write to **any** project, when the admin granted
  it one. The fix is an allowlist in the app, checked before the write, not a
  configuration value the model can be talked into changing. `hico-pmo` does this
  with a frozen set of writable project keys.
- A file-reading app that accepts a path from the request and reads anything the
  container can see. Path traversal, but the blast radius is "every credential
  the platform injected".
- An app that calls a `value`-access source using fields that source did not
  declare in the manifest.

Check it the same way as generic BOLA: take every endpoint that accepts an
identifier — a project key, a table id, a path, a folder — and ask what happens
if it is replaced with something the admin never granted. **The answer should be
a refusal from the app's own code**, not "the upstream system would probably
reject it".

---

## Shared context is a design finding, not a code finding

A VCA runs on a shared team identity today. Every person using it sees
everything the app can see.

If the app holds anything that should be per-person — someone's own drafts,
salary data, HR cases, a personal mailbox, an audit trail naming individuals —
that is a **finding**, and it is not fixable in code. Report it as a design
issue and route it to the Vault platform team (§1 rule 7). Do not:

- add a login to separate users (forbidden, and the whole point of the rule)
- add a "select who you are" dropdown (that is a login with no password)
- quietly ship it and hope the data is not sensitive

The honest outcome is sometimes "this app should not hold this data until Forge
lends identity". Say that.

---

## The secrets a VCA actually has

Auth is out of scope, but a VCA is *more* secret-bearing than a typical small
app, not less. Audit these specifically:

1. **`VAULT_API_KEY`** — the app's own credential. Injected by the platform,
   never committed, never logged, never sent to the frontend, never parsed. A
   traceback that prints request headers leaks it.
2. **Resolved values from `/resolve`** — real credentials for `value`-access
   sources. In memory only. Never written to disk, a cache file, a log line, or
   an error message. Never returned by any endpoint.
3. **Anything a `value` source's own client sends** — a CRM or SMTP client
   inside the app carries live credentials. It gets the same scrutiny as
   `vault_client.py`.

For each: grep, then check the error paths, because that is where secrets escape
even when the happy path is clean.

---

## Severity, translated for this platform

The audit's severities assume public internet exposure. Adjust:

- **Critical** — app-owned auth of any kind (compliance); a secret in source or
  git history; the app able to write outside its granted scope; injection into a
  `value` source's live system.
- **High** — resolved values reachable through any endpoint or log; a
  destructive endpoint with no confirmation step; dependency CVE with a known
  exploit; mass assignment on a handler that touches an external system.
- **Medium** — verbose errors, missing security headers, dependency CVEs without
  a known exploit, injection into data the app only shows to itself.
- **Design finding** — per-person data on shared context; anything needing
  identity. Not a severity; it goes to the platform team.

---

## What to tell a citizen developer

Two sentences, and they carry most of the value:

1. **You are not responsible for building security here — you are responsible
   for not building around it.** The platform holds the credentials, the login
   and the network boundary. Adding your own version of any of those is the
   failure mode, not the fix.
2. **Everything your app answers on is public inside the company.** If an
   endpoint would embarrass you on a poster, it needs to not exist, not to be
   hidden.
