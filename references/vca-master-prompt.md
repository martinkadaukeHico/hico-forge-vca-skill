# HICO Forge — VCA Master Prompt (v1.1)

*For humans: give this entire file to the AI coding tool before the first line of code exists — drop it into the empty repo as `CLAUDE.md` (Claude Code), add it as project rules/instructions (Cursor, Windsurf, ...), or paste it as the very first message together with your app idea.*

*Why: an app built without these rules has to be rewritten before it can run in Forge (we did that migration once, with Wochenradar — the point of this document is to never do it again). An app built with them is compliant on day one.*

*Questions / gaps → HICO Vault platform team. Source of truth for this file: `vault/docs/forge-vca-master-prompt.md`.*

You are building a **VCA — Vault Consuming Application** — for the HICO Forge platform. Forge apps are small, single-container web apps that run embedded inside the HICO Vault platform and borrow everything sensitive from Vault: AI access, credentials, connections, budgets, audit. The app itself owns no secrets.

Follow every rule in this document. If the user's app idea conflicts with a rule, say so and propose a compliant alternative — never silently violate a rule. If the app needs something this document does not cover (a new kind of external resource, agentic AI, streaming, per-user OAuth), stop and tell the user to clear it with the Vault platform team before you build around it.

---

## 1. Golden rules (non-negotiable)

1. **Zero secrets in this app.** The only credentials that may ever exist — in code, config, env files, Docker image, or git history — are `VAULT_URL` and `VAULT_API_KEY`. No provider API keys, no passwords, no tokens, no connection strings. Ever.
2. **All AI goes through Vault.** Never install or import a provider SDK (`openai`, `anthropic`, `litellm`, `google-generativeai`, `cohere`, `mistralai`, `boto3` for Bedrock, LangChain LLM classes, `ollama`, ...). Never call a provider host directly. AI = `POST {VAULT_URL}/api/v1/broker/ai/invoke` with the app's Vault key.
3. **Jobs, not models.** The app never chooses, names, or hardcodes an AI model. It names a *job* (`summarize_ticket`, `draft_reply`); the Vault admin decides which model serves each job. No model name appears anywhere in the codebase.
4. **Every external resource is declared.** Anything the app needs from outside its own container — a database, a CRM, mail, AI — is declared in `manifest.json` and obtained at runtime from Vault's `/resolve`. If it is not in the manifest, the app must not use it. If the code stops using a source, remove it from the manifest.
5. **One chokepoint per resource.** Exactly one module talks to Vault: `backend/vault_client.py`. Exactly one module per resource type consumes what it returns (one AI helper, one CRM client, ...). No scattered `os.environ` reads, no second config path, no direct `httpx`/`requests` calls sprinkled through the code.
6. **Fail loud, degrade gracefully.** Exactly two failure modes, never mixed up:
   - **Not configured at all** — `VAULT_URL` or `VAULT_API_KEY` missing outside mock mode. This is a deployment error: crash at startup with a clear message.
   - **Configured but Vault is unhappy** — unreachable, erroring, or a source is pending/denied/unfilled. The process stays alive, `/api/vault/status` reports it, and the affected feature disables itself with a clear UI state. Never a crash loop, never a silent local fallback.
7. **The app owns no identity.** A VCA never implements its own login, user table, password handling, or role system — authentication belongs to HICO Vault. Until Vault SSO ships (VAULT-2) a VCA has no per-user identity at all, so design it as a shared/team-context tool. If the app idea genuinely needs to know which user is acting (per-user data separation, roles, approvals, an audit trail naming people), stop and clear it with the Vault platform team — do not build an interim login to bridge the gap.

## 2. What Vault owns vs. what the app owns

| Vault owns (the app borrows) | The app owns |
|---|---|
| AI models + provider keys, job→model mapping | Its UI and business logic |
| AI budget, metering, rate limits | Its own local state (SQLite) |
| Credentials for external systems (CRM, DB, SMTP, ...) | Its manifest (declaring what it needs) |
| Grant decisions (which resources this app may use) | Its Docker image |
| Audit trail of app activity | — |
| User login / SSO / all identity (VAULT-2) | — (never builds its own — §1 rule 7) |

**Device-local resources do not exist in Forge.** The app runs in a Docker container on a server — it cannot automate desktop Outlook (COM), read the user's local files, talk to USB devices, or shell out to locally installed tools (e.g. a local `claude` CLI). If the app idea depends on any of these, stop and flag it to the user: the feature must be redesigned (usually: server-side equivalent via a Vault-brokered resource) or the app is not Forge-compatible.

## 3. Prescribed stack (mandatory)

One Docker container, one exposed port. Inside it:

- **Backend:** Python 3.12+, FastAPI, uvicorn. All routes under `/api/*`.
- **Frontend:** React + Vite + TypeScript, built with `npm run build` into `frontend/dist`, served by FastAPI as static files at `/`. Single origin — no CORS configuration, no separate frontend server in production.
- **App-local state:** SQLite, file under `/data` (volume-mounted) in the container. No credentials needed — that is the point. Company-shared data does not go here; it goes through a manifest-declared connection.
- The Dockerfile creates `/data`. For native dev (§12 step 1, before any container exists) fall back to a repo-local `./data/` — but only ever use `/data` if it already exists as a directory. Never `mkdir` an absolute `/data` from application code: on Windows that resolves to the current drive root and silently creates a real `C:\data\`. Name the SQLite file after the app key (`/data/<app>.db`) so two local runs on one host cannot collide.

Repo layout:

```
myapp/
├── CLAUDE.md               # this file
├── manifest.json           # the resource manifest (single source of truth)
├── Dockerfile              # multi-stage: build frontend, then python runtime
├── README.md               # incl. AI-jobs table + env-vars table
├── backend/
│   ├── main.py             # FastAPI app; serves /api/* + frontend/dist
│   ├── vault_client.py     # THE only module that talks to Vault (§6)
│   ├── vault_mock.py       # canned Vault responses for VAULT_MOCK=1 (§7)
│   ├── ai_jobs.py          # every AI job name as a constant (§9)
│   └── ...                 # business logic, one module per resource type
└── frontend/
    └── src/ ...
```

**Embeddability** (the app runs inside Vault's iframe):

- Send `Content-Security-Policy: frame-ancestors <FRAME_ANCESTORS>` from env (default `'self'`; production = the Vault origin). Never send `X-Frame-Options: DENY`.
- If the app sets cookies: `SameSite=None; Secure` — otherwise login inside the iframe silently fails.
- Never use top-level navigation, `window.top`, or popups for core flows. The app must be fully usable inside an iframe.

**No login in the app.** See §1 rule 7 — identity is Vault's, and there is none available to a VCA until VAULT-2. Build no auth; flag the gap if the idea needs one.

### Environment variables (the complete list)

| Variable | Required | Purpose |
|---|---|---|
| `VAULT_URL` | prod/stage/dev-integration | Base URL of HICO Vault (e.g. `https://vault.example.com`) |
| `VAULT_API_KEY` | prod/stage/dev-integration | The app's `hvk_...` key, issued by the Vault admin. Injected by the platform — never committed. |
| `VAULT_MOCK` | dev only | `1` = use canned responses from `vault_mock.py`; no Vault needed |
| `VAULT_MOCK_PENDING` / `VAULT_MOCK_DENIED` / `VAULT_MOCK_MISSING` | dev only | Comma-separated source keys (for MISSING: `source.field`) to force degraded states in mock so the §5.1 UI states are testable without an admin. Read only inside `vault_mock.py` — see §7 |
| `APP_ENV` | always | `dev` \| `stage` \| `prod` — mock mode refuses to start when prod |
| `PORT` | optional | HTTP port (default 8000) |
| `FRAME_ANCESTORS` | prod/stage | CSP `frame-ancestors` value (the Vault origin) |

Local dev may use a git-ignored `.env` file; the only secret it may ever contain is a dev-environment `VAULT_API_KEY`. Do not invent additional config files or env variables for external resources — those come from `/resolve`.

## 4. The manifest (`manifest.json`)

The manifest is the app's secret-free declaration of everything it needs from Vault. Vault ingests it, shows the admin a form, the admin fills values and grants or denies each source. New sources always start `pending` — the app declares, Vault decides.

It must describe the app you actually built — every declared source is used by the code, every external dependency in the code has a source. This is checked at review.

### Schema

Top level: `app` (string, the app's key), `manifest_version` (integer ≥ 1, bump on every change), `sources` (non-empty list).

Each source:

| Field | Values | Notes |
|---|---|---|
| `key` | string, required | stable identifier, e.g. `ai`, `crm` |
| `label` | string | shown to the admin |
| `kind` | `secret_group` \| `connection` \| `oauth_delegated` | default `secret_group` |
| `access` | `value` \| `proxy` \| `oauth_delegated` | see below; default `value` (`oauth_delegated` kind defaults to `oauth_delegated`) |
| `required` | bool | app cannot function without it |
| `fields` | list | see below |
| `note`, `provider`, `scopes`, `test`, `redirect_uri` | optional | free extras shown to the admin |

Each field: `key` (required), `label`, `type` ∈ `string` \| `secret` \| `url` \| `int` \| `bool` \| `enum` (default `string`), `secret` (bool, default true iff `type: secret`), `required` (bool), `default`, `placeholder`. No duplicate source keys; no duplicate field keys within a source.

### Choosing `access` — the core design decision per source

- **`proxy`** — Vault keeps the secret and the app calls a Vault endpoint instead. AI is always `proxy`. The app never receives the provider key; `/resolve` returns only a `proxy_url`. Never declare an `api_key` field the app expects to receive for a `proxy` source — it will not be returned.
- **`value`** — the app receives the real values (including secrets) at runtime via `/resolve` and connects directly. For resources Vault cannot proxy: databases, CRM (e.g. Odoo XML-RPC), SMTP. Values live in memory only — never write them to disk or logs.
  - Vault hands over only the *values* the manifest declares — it says nothing about *how to call that system*. The request shape (endpoint paths, HTTP verbs, auth header style, payload schema) is the app's own knowledge of that specific product. Never invent it. If the user has not supplied the target system's API documentation, say so and ask — a plausible-looking guess at someone's REST contract is a silent integration failure, not a working feature.
- **`oauth_delegated`** — per-user consent (e.g. MS Graph). Not available yet (VAULT-2). You may declare it for the future; it will resolve as `pending`. Do not build features that depend on it working today.

### Example

```json
{
  "app": "myapp",
  "manifest_version": 1,
  "sources": [
    {
      "key": "ai",
      "label": "AI (via Vault broker)",
      "kind": "secret_group",
      "access": "proxy",
      "required": true,
      "fields": [],
      "note": "Jobs used: summarize_ticket, draft_reply (see README)"
    },
    {
      "key": "crm",
      "label": "Odoo CRM (XML-RPC)",
      "kind": "connection",
      "access": "value",
      "required": false,
      "fields": [
        { "key": "url", "type": "url", "required": true },
        { "key": "db", "type": "string", "required": true },
        { "key": "username", "type": "string", "required": true },
        { "key": "api_key", "type": "secret", "secret": true, "required": true }
      ]
    }
  ]
}
```

The AI source usually has no fields — which model serves which job is decided in Vault's admin UI (AI Jobs), not in the manifest. List the app's job names in the `note` and in the README instead.

## 5. Vault API contracts

Authentication for both endpoints: `Authorization: Bearer <VAULT_API_KEY>` (an opaque `hvk_<env>_<keyid>_<secret>` token — treat as an opaque string, never parse or log it).

### 5.1 `GET {VAULT_URL}/api/v1/resolve` — fetch granted resource config

```json
{
  "app": "myapp",
  "granted": {
    "ai":  { "access": "proxy", "proxy_url": "/api/v1/broker/ai/invoke" },
    "crm": { "access": "value", "url": "https://crm.example.com", "db": "prod",
             "username": "svc-myapp", "api_key": "<real secret, in memory only>" }
  },
  "denied": ["some_source"],
  "pending": ["another_source"],
  "missing_required": ["crm.api_key"]
}
```

- int/bool fields arrive properly typed (a real `587`, not `"587"`).
- `proxy` sources never include secrets — only `proxy_url` plus non-secret config fields.
- Call `/resolve` at startup and cache in memory; refresh on demand (e.g. from `/api/vault/status`). Never persist the response.

Required per-source behavior:

| State | App behavior |
|---|---|
| in `granted`, not in `missing_required` | feature enabled |
| in `pending` | feature disabled — UI: "Awaiting approval in HICO Vault" |
| in `denied` | feature disabled — UI: "Not approved in HICO Vault" |
| granted but in `missing_required` | feature disabled — UI: "Awaiting configuration in HICO Vault" |

**Degradation is always feature-level — never app-level.** A disabled source disables exactly the features that need it; everything else stays fully usable. If AI is unavailable, the user can still open the app, enter data, and save it — they just cannot run the AI actions, which show the §5.1 message.

`required: true` is a signal to the admin ("this app is not doing its job until you configure this"), surfaced as a prominent persistent banner. It is not an instruction to block the app: never render a full-screen wall or a crash loop because a required source is pending.

### 5.2 `POST {VAULT_URL}/api/v1/broker/ai/invoke` — run an AI job

Request / response:

```json
{ "job": "summarize_ticket",
  "messages": [ { "role": "user", "content": "..." } ],
  "max_output_tokens": 2048 }
```

```json
{ "content": "…the answer…", "model": "gpt-5-mini",
  "input_tokens": 14, "output_tokens": 312, "points_charged": "0.1038" }
```

- `role` ∈ `system` \| `user` \| `assistant`. Non-streaming: the full answer arrives at once — build the UX with loading states, never expect token streaming.
- Always send `max_output_tokens`, default 2048, never below 1024. Reasoning models spend output tokens on internal reasoning before any visible text — a small cap returns an empty answer that still costs money.
- Rate limit: 30 requests/minute per key. Keep AI calls bounded: one user action → a small fixed number of invokes. No unbounded loops.

Error handling (mandatory):

| Status | Meaning | App behavior |
|---|---|---|
| 401 | key invalid / expired / revoked | UI: "Vault key invalid — contact your admin". No retry. |
| 403 | key lacks the `ai:invoke` scope | same as 401 |
| 409 | job has no model assigned yet | UI: "AI job awaiting configuration in Vault". No retry — the first call auto-registers the job so the admin can see and configure it. |
| 429 | budget exhausted or rate limit | back off, surface the message. Never retry-loop. |
| 502 | upstream provider failed | one retry after a short delay is acceptable, then surface. |

### 5.3 What the broker does not do (v1)

- **No agentic AI:** no web search, no tool use, no browsing, no file access, no computer use. If the app idea needs the model to look something up or act, stop and flag it to the user — this needs the platform team, do not emulate it with loops of plain completions.
- **No streaming, no embeddings, no image generation.** Plain chat completions only.
- **No structured-output mode:** no JSON mode, no function calling, no schema enforcement. The broker forwards plain messages and returns plain text. See §5.4 — classification and extraction jobs are still perfectly buildable, they just need a parse convention.

### 5.4 Jobs that need a structured answer (the required convention)

Plenty of useful jobs are classifications (`classify_fit`, `classify_lead`) or extractions. With no JSON mode (§5.3) they need discipline instead:

1. Define the closed set of valid outputs as a constant next to the job name, in `ai_jobs.py`. The set is app code — never something the model invents.
2. Constrain via the system message: state the exact allowed values and that the reply must be one of them and nothing else.
3. Parse defensively: trimmed, case-insensitive exact match against the constant set.
4. An unparseable answer is an explicit outcome, not a guess. Map it to a visible "unknown / needs review" state. Never coerce it to the nearest-looking value, and never retry-loop to coax the format — that burns budget (§9) and still has no guarantee.

```python
# in ai_jobs.py
CLASSIFY_FIT = "classify_fit"
FIT_LEVELS = ("strong_yes", "yes", "no", "strong_no")   # the closed set; app-owned
FIT_UNKNOWN = "unknown"                                  # model didn't comply
```

For multi-field extraction, prefer one line per field with a fixed `key: value` prefix over asking for JSON — it degrades far more predictably when the model adds prose.

## 6. `backend/vault_client.py` — the required chokepoint (reference implementation)

See `assets/backend/vault_client.py` in this skill for the full, ready-to-copy reference implementation. Adapt names to the app, keep the structure. Every other module gets Vault data only by importing this one.

Rules enforced there and nowhere else:
- config from env only: `VAULT_URL`, `VAULT_API_KEY`
- `VAULT_MOCK=1` → canned responses from `vault_mock.py` (dev only, refuses in prod)
- no other module may read `VAULT_*` environment variables

Key behaviors:
- `check_configured()` — call once at startup: raises `VaultConfigError` → the app must not boot. Deliberately does **not** contact Vault. An unreachable Vault must leave the app running so `/api/vault/status` can report `vault: unreachable` (§1 rule 6, §8).
- `resolve()` — granted resource config. Call at startup, cache in memory only.
- `ai_invoke(job, messages, max_output_tokens=2048)` — runs one AI job through Vault. Retries exactly once on 502 (upstream provider failure, §5.2). Every other status is raised straight to the caller with `status_code` set — no retry, and 429 must **never** be retried.
- `VaultError` carries a `status_code` (Vault's HTTP status, or `None` when Vault was unreachable) — callers branch on it to implement the §5.2 table, never on the message string.
- `VaultConfigError` (subclass of `VaultError`) is the only Vault failure that may stop the app booting (§1 rule 6).

The API layer maps `VaultError.status_code` to the §5.2 user-facing states (401/403 → "key invalid", 409 → "job awaiting configuration", 429 → surface and back off, `None` → "Vault unreachable"). That mapping lives in one place too — do not repeat it per route.

## 7. Mock mode (`VAULT_MOCK=1`) — required in every VCA

The app must be fully buildable and clickable before it is registered in Vault — with zero admin involvement. That is what mock mode is for.

Hard rules:

1. The mock lives in exactly one file, `backend/vault_mock.py`, and is reached only through the `mock_enabled()` branch inside `vault_client.py`. No other file may check `VAULT_MOCK`.
2. Mock returns must have exactly the real contract shapes (§5) — same keys, same types.
3. Mock fixtures stay in sync with `manifest.json`: by default every declared source appears as granted, so every feature is exercisable offline.
4. The degraded states must be reachable too. `VAULT_MOCK_PENDING`, `VAULT_MOCK_DENIED` and `VAULT_MOCK_MISSING` (§3) move named sources out of `granted` so the §5.1 UI states can be verified with no Vault and no admin. These are the only other env vars `vault_mock.py` may read, and no other file may read them. Without this a developer cannot satisfy §11 checklist item 6 before registration.
5. Mock output is unmistakable: free-text AI answers are prefixed `[MOCK:<job>]`, the `model` is always `"mock"`, and the UI shows a persistent banner ("Vault mock mode — no real AI") whenever `/api/vault/status` reports mock.
   - **Exception** — closed-set jobs (§5.4) return the bare label, unprefixed. Their valid output space is the closed set, so a `[MOCK:]` prefix would make every mocked classification fail the app's own exact-match parse. `model: "mock"` plus the banner already make mock mode unmistakable; do not weaken the parser to accommodate a marker.
6. The mock may be job-aware — returning a valid closed-set label for a §5.4 classification job, for example — as long as the contract shape (rule 2) and the marking rules above hold. A mock that returns unparseable text for every job makes the app's own parse path untestable.
7. Mock mode refuses to start in prod (enforced in `mock_enabled()`) and contains no real values — no real URLs, no real keys, nothing copy-pasted from a live system.

See `assets/backend/vault_mock.py` in this skill for the full reference implementation.

Run the app once per degraded state to satisfy §11 item 6, e.g.:

```
VAULT_MOCK=1 APP_ENV=dev VAULT_MOCK_PENDING=ai npm run dev
```

## 8. Required endpoints (every VCA serves these)

| Endpoint | Returns |
|---|---|
| `GET /health` | `{"status": "ok", "app": "myapp", "version": "..."}` |
| `GET /api/vault/manifest` | the contents of `manifest.json`, verbatim |
| `GET /api/vault/status` | `{"mode": "real" \| "mock", "vault": "ok" \| "unreachable", "granted": [...keys], "pending": [...], "denied": [...], "missing_required": [...]}` — keys and states only, never values, never secrets |

`/api/vault/manifest` is how Vault will pull the manifest automatically in the future (today the admin pastes it) — serve it by reading `manifest.json`, never by hardcoding a second copy of it in Python.

`/api/vault/status` is the admin's and developer's one-glance integration check. It must answer even when Vault is unreachable — that is exactly when someone is looking at it. Report `vault: "unreachable"` and empty state lists; never let it 500, and never let it be the reason the app appears dead.

## 9. AI usage rules

- Job names are stable snake_case verb_noun identifiers: `summarize_ticket`, `draft_reply`, `classify_lead`. Renaming a job means the admin must reconfigure it — treat names as API.
- Every job name is a constant in `backend/ai_jobs.py` — the only place job strings are defined:
  ```python
  """Every AI job this app calls. Names are API — admin configures models per job."""
  SUMMARIZE_TICKET = "summarize_ticket"
  DRAFT_REPLY = "draft_reply"
  ```
- A job that must return a structured answer (a classification, an extraction) also owns its closed set of valid outputs as a constant here — see §5.4 for the required parse convention.
- README must contain the jobs table: job key, what it does, expected calls/day, suggested model tier (fast/cheap vs strong). The admin uses it to assign models and set the budget.
- One distinct task = one job. Do not funnel unrelated tasks through one generic job (kills per-task model governance); do not create ten jobs for one task.
- Budget awareness: every call costs points from the app's own budget. Cache AI results where the same input recurs; never call AI in a render loop, a poller, or a retry loop.

## 10. Forbidden — the tool must never do any of these

- Install/import a provider SDK: `openai`, `anthropic`, `litellm`, `google-generativeai`, `cohere`, `mistralai`, Bedrock via `boto3`, `ollama`, LangChain/LlamaIndex LLM classes.
- HTTP to any AI provider host (`api.openai.com`, `api.anthropic.com`, `*.openai.azure.com`, `generativelanguage.googleapis.com`, ...). In production, egress is firewalled to Vault only — such code is dead on arrival.
- A model name anywhere in the codebase (`gpt-*`, `claude-*`, `gemini-*`, ...).
- Any secret other than a dev `VAULT_API_KEY` in `.env`; any secret at all in code, `docker-compose.yml`, or committed files.
- Reading `VAULT_URL` / `VAULT_API_KEY` / `VAULT_MOCK` outside `vault_client.py`.
- Writing `/resolve` values (or the response) to disk, DB, or logs.
- A local fallback that "works without Vault" outside the mock (e.g. "if no Vault, use env var X") — that is exactly the secret-smuggling path this platform exists to close.
- Streaming AI UX, agentic AI emulation, unbounded AI loops.
- `X-Frame-Options: DENY`, cookies without `SameSite=None; Secure`, `window.top` navigation — anything that breaks iframe embedding.

## 11. Compliance self-check — run before declaring the app done

Run `scripts/compliance_check.sh <repo-path>` from this skill and show the user the results (expected: no matches unless stated). It implements the seven greps below.

```bash
# Skip compiled/build artifacts — they exist by the time you run this (you have
# already started the app), and a .pyc will match check 3 from its own bytecode.
EXCL='--exclude-dir=__pycache__ --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.venv --exclude-dir=.git --exclude=*.pyc'

# 1. No provider SDKs
grep -rniE $EXCL "import (openai|anthropic|litellm|cohere|mistralai)|from (openai|anthropic|litellm)|google\.generativeai" backend/ frontend/src/

# 2. No provider hosts
grep -rniE $EXCL "api\.openai\.com|api\.anthropic\.com|openai\.azure\.com|generativelanguage\.googleapis" backend/ frontend/src/

# 3. No model names (mock model is literally "mock")
grep -rniE $EXCL "gpt-[0-9]|claude-|gemini-|llama-" backend/ frontend/src/

# 4. Chokepoint integrity — VAULT_* read only inside the chokepoint
#    (vault_mock.py may additionally read VAULT_MOCK_PENDING/_DENIED/_MISSING — §7 rule 4)
grep -rn $EXCL "VAULT_URL\|VAULT_API_KEY\|VAULT_MOCK" backend/ | grep -v "vault_client.py" | grep -v "vault_mock.py"

# 5. All outbound HTTP accounted for — every hit outside vault_client.py
#    must map 1:1 to a value-access source in manifest.json
grep -rn $EXCL "httpx\.\|requests\." backend/ | grep -v "vault_client.py"

# 6. Secrets scan — review every hit; only obvious test fixtures are acceptable
grep -rniE $EXCL "(api_key|apikey|secret|password|token)\s*[:=]\s*['\"][^'\"]{8,}" backend/ frontend/src/

# 7. No app-owned authentication (§1 rule 7) — review any hit
grep -rniE $EXCL "login|password_hash|bcrypt|passlib|session_cookie|jwt" backend/ frontend/src/
```

Checklist:

- [ ] `manifest.json` matches the code — every source used, every external dependency declared
- [ ] every AI call site uses a constant from `backend/ai_jobs.py`; jobs table in README
- [ ] every structured-output job has a closed set + defensive parse + a visible unknown state (§5.4)
- [ ] app fully usable with `VAULT_MOCK=1`; mock banner visible; refuses mock when `APP_ENV=prod`
- [ ] docker build succeeds; the container serves `/health`, `/api/vault/manifest`, `/api/vault/status`
- [ ] app renders and is fully usable inside an iframe
- [ ] pending / denied / missing_required sources disable features with clear UI states — no crash, no silent fallback. Verify by actually running with `VAULT_MOCK_PENDING` / `_DENIED` / `_MISSING` (§7 rule 4), not by reading the code
- [ ] degradation is feature-level: with every source withheld the app still opens and its independent features still work (§5.1)
- [ ] missing `VAULT_URL`/`VAULT_API_KEY` crashes at startup; Vault merely unreachable leaves the app up and reports it via `/api/vault/status` (§1 rule 6)
- [ ] AI error statuses (401/403/409/429/502) produce the §5.2 behaviors, branching on `VaultError.status_code` — never on message text
- [ ] no app-owned login / user table / role system (§1 rule 7); identity gaps flagged to the user, not bridged
- [ ] every value-source request shape came from that system's real API docs — nothing invented (§4)
- [ ] README: jobs table + env-vars table + how to run (mock, degraded-mock, and real)

## 12. Lifecycle: from empty repo to running in Forge

1. **Build in mock** — `VAULT_MOCK=1`, `APP_ENV=dev`. Full app, all features, canned Vault responses. No admin needed.
2. **Register** — hand the Vault admin the handoff package (below). Admin: registers the app in App Integrations, pastes `manifest.json`, grants sources + fills values, issues a dev `hvk_` key, assigns models to the AI jobs.
3. **Integrate** — unset `VAULT_MOCK`, set `VAULT_URL` + dev `VAULT_API_KEY`. Check `GET /api/vault/status` shows `mode: real`, `vault: ok` and the expected grants; run every AI job once for real.
4. **Deliver** — the platform team deploys the container; `VAULT_URL`/`VAULT_API_KEY` (stage/prod keys) are injected by the platform, never shipped in the image.

### Handoff package (produce this as `HANDOFF.md` at the end)

- App name, one-paragraph description, owner (person + team)
- `manifest.json` (final)
- AI jobs table: job key · purpose · expected calls/day · suggested tier (fast/cheap vs strong)
- Estimated monthly AI volume → suggested budget
- Container: image name, exposed port, `/health` path
- Env vars the platform must inject (from the §3 table)
- Any identity/auth gap flagged under §1 rule 7, and any value-source whose request shape is still unconfirmed (§4)

Items 1 and 4 are provisional at this stage — a brand-new app has no production traffic and possibly no assigned owner yet. Write your best estimate and label it as such rather than leaving it blank or inventing a precise-looking number.

---

*v1.1 · 2026-07-27 · maintained by the HICO Vault platform team*

### Changelog

- **v1.1** — field-tested by building a real app from this document alone; fixed everything that test surfaced. Four were places where following v1 literally was impossible: `VaultError` carried no status code yet §5.2 mandates per-status behavior (§6); §1/§6/§8 described three different startup-failure models (§1 rule 6, `check_configured()`); mock granted every source yet the checklist demanded verifying pending/denied (§7 rule 4 + `VAULT_MOCK_*`); and `classify_*` jobs were encouraged with no structured-output path (§5.4). Also added: no app-owned identity (§1 rule 7), feature-level-only degradation (§5.1), a warning never to invent a value-source request shape (§4), `/data` native-dev guidance, and build-artifact exclusions in the §11 greps.
- **v1** — 2026-07-23, initial version.

*No reference implementation is cited yet: Wochenradar predates this document and would fail several of its own §11 checks (its manifest is hardcoded in Python, and it names a model). The Forge starter kit will be the reference once it lands.*
