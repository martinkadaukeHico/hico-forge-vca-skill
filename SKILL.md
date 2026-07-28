---
name: hico-forge-vca
description: Enforces the HICO Forge "VCA" (Vault Consuming Application) platform rules whenever you or a colleague is building, scaffolding, or vibe-coding a new internal web app, tool, dashboard, or prototype at HICO — even if the request never says "Forge," "Vault," or "VCA" by name. Apps built without these rules (no secrets in the app, all AI routed through Vault by job name not model name, a single vault_client.py chokepoint, manifest.json declaring every external resource, no app-owned login) have to be rewritten before they can run on the platform. Use this skill at the very start of any new app build for HICO — before writing the first line of code — and again near the end to run the compliance self-check. Also use it if someone is midway through building an internal app and it's not yet clear whether it follows these rules, or if they mention manifest.json, vault_client.py, VAULT_MOCK, or "run this in Forge."
---

# HICO Forge VCA compliance

HICO Forge apps ("VCAs") are small single-container web apps that borrow AI access, credentials, and identity from HICO Vault instead of owning any of it themselves. The full rules live in `references/vca-master-prompt.md` (HICO's "VCA Master Prompt v1.1" — the source of truth; if your copy of this skill and the live doc at `vault/docs/forge-vca-master-prompt.md` ever disagree, the live doc wins and this skill should be updated).

The reason this skill exists: an app built without these rules gets rewritten before it can run on the platform (HICO already did that migration once). Following the rules from the first commit means the app is compliant on day one instead.

## When you're starting a new app (do this first, before any code)

1. **Read `references/vca-master-prompt.md` now**, in full — don't skim it. It's the actual spec; this SKILL.md is just the entry point and workflow around it.
2. **Sanity-check the app idea against §1 (golden rules) and §2 before writing anything.** A few conflicts come up constantly — catch them now, not after half the app is built:
   - Does it need to know *which person* is acting (per-user data, approvals, an audit trail naming people)? There is no per-user identity available to a VCA yet (§1 rule 7) — flag this to the user and ask whether a shared/team-context design is acceptable, rather than quietly building a login screen.
   - Does it depend on anything that only exists on someone's desktop (local Outlook, local files, a USB device, a locally-installed CLI)? Device-local resources don't exist in Forge (§2) — flag it and propose a server-side equivalent, or say the idea isn't Forge-compatible as described.
   - Does it want the model to browse, search, or take actions ("agentic" AI)? The broker is plain chat completions only (§5.3) — flag it rather than faking it with loops of completions.
   - Does it need a live external system (CRM, mailbox, another API)? You'll need that *system's real API docs* before writing the client for it (§4) — ask the user for them rather than guessing at endpoints and payload shapes. A guessed integration looks done and is actually broken.
   If the idea conflicts with a rule, say so and propose a compliant alternative out loud — never quietly build the noncompliant version because it's easier or the user didn't ask about Vault specifically.
3. **Scaffold the repo per §3's layout.** Copy the reference implementations in `assets/backend/` into the new repo's `backend/` directory as your starting point rather than writing `vault_client.py` and `vault_mock.py` from scratch — they already encode the retry/error/status-code rules from §5.2 and §6 correctly, including the easy-to-get-wrong bits (retry once on 502 and never on 429, `VaultConfigError` vs. plain `VaultError`, mock refusing to start in prod). Adapt `assets/backend/ai_jobs.py` and `assets/manifest.example.json` to the app's actual jobs and sources — don't ship the placeholders as-is.
4. **Write `CLAUDE.md` in the new repo's root as a copy of `references/vca-master-prompt.md`.** This is what makes the rules durable across sessions: the next time Claude Code (yours or a colleague's) opens this repo, it reads `CLAUDE.md` automatically and inherits the same constraints, even without this skill triggering again.
5. Build the app. Keep coming back to §§4–10 as you add each piece — the manifest schema, the `/resolve` and AI-broker contracts, the required endpoints (§8), and the forbidden list (§10) are the parts most likely to matter for any given feature.

## When you're mid-build, or resuming someone else's app

Check whether `CLAUDE.md` already contains the VCA Master Prompt. If not, that's a gap — add it (per step 4 above) rather than assuming the app is exempt. Then read through what's already been built against §§1, 6, 7, 9, and 10 before adding more: it's much cheaper to catch a provider SDK import or a stray `os.environ.get("VAULT_...")` now than after the feature is finished.

## When the user says the app is now connected to Forge / has a dev, stage, or prod key

This is a specific, recurring moment worth handling deliberately: the user says something like "we've registered this in Forge now," "it has a key," or "it can connect to APIs like X now" — and wants you to keep building. Getting this moment wrong in either direction is costly: block too hard and you stall a developer who's actually asking you to build something completely compliant; wave it through and you bypass the entire point of this platform.

What actually changed, mechanically, is narrow: `VAULT_URL` and a real `VAULT_API_KEY` are now set (§12 step 3), so `vault_client.py`'s `mock_enabled()` branch stops firing, and whatever sources the admin has granted now show up for real in `/resolve` and `/api/vault/status`. That's it. It does **not** change §1's golden rules, it does not add any new manifest source, and it does not grant permission to reach any external system directly — it only moves already-declared, already-granted sources from "mocked" to "real."

So when a request like this comes in, apply one rule and move on — don't spiral into an extended investigation of which cloud product the user might mean, the way that costs a lot of back-and-forth when the answer is a single sentence:

- **If the capability in question is AI, the answer is always the same, regardless of which model or cloud the Vault admin wired up behind the job: it still goes through the broker, addressed by job name (§1 rule 2).** The whole point of job-based AI (§1 rule 3) is that the underlying provider is invisible to the VCA. Hearing "we can use Azure/OpenAI/Bedrock now" never means "add that SDK" or "call that host" — it means "the admin has assigned a model to this job," which requires no code change at all beyond calling `ai_invoke(job, ...)` like always. State this once, in a sentence, and keep building the feature itself (the prompt, the job, the parsing) — that part was never blocked and doesn't need to wait on this clarification.
- **If the capability is a genuinely different external system** (a search API, a new SaaS product, Odoo, anything that isn't "the model behind an AI job") **— a live key still doesn't let you build it without knowing what it actually is.** §4's rule against inventing a request shape doesn't get waived by having a Vault key; you still need the product name and its real API docs before writing a client for it, and it still needs a manifest source (starting `pending` until the admin grants it). But once you have both of those, build it for real — this is exactly the case the platform exists to support, and there's no reason to hold back or keep testing against the mock once a real, granted, documented source exists.
- **When it's ambiguous which of the two situations you're in** (as in "APIs like Azure" — could be Azure OpenAI, could be a genuinely new Azure service), ask exactly one crisp question to disambiguate, and build whatever part of the task doesn't depend on the answer in the meantime, rather than producing a long chain of internal deliberation about it or stalling the whole task on it.
- **Never let "we're connected now" become an implicit excuse to add a source to the manifest that wasn't there before, or to skip declaring one, because it "already works."** Every source still goes through §4's declare → pending → admin grants flow, key or no key.

## When the app is close to done (before declaring it done)

Run the compliance self-check:

```bash
bash scripts/compliance_check.sh /path/to/the/repo
```

This runs the seven greps from §11 (provider SDKs, provider hosts, model names, chokepoint integrity, unaccounted outbound HTTP, a secrets scan, and app-owned-auth signals) and prints PASS or REVIEW for each with the matching lines. A REVIEW hit is not automatically a violation — e.g. check 5 flags every `httpx`/`requests` call outside `vault_client.py`, which is expected and fine for a `value`-access source's own client (like a CRM client), as long as it's declared in `manifest.json` and only uses fields that source declares. Look at each hit and decide; don't just eyeball "no matches" as the only acceptable outcome, and don't wave through a hit without checking it against the corresponding rule in `references/vca-master-prompt.md` §11.

Then walk the checklist in §11 of the reference doc — most of it isn't grep-able (does the app degrade feature-by-feature when a source is denied? does it actually crash on missing `VAULT_URL`? does mock mode show the banner?) and needs to be verified by actually running the app with `VAULT_MOCK=1` and then again with `VAULT_MOCK_PENDING`/`_DENIED`/`_MISSING` set, not just by reading the code.

Finish by producing `HANDOFF.md` per §12 — the app name/owner, the final `manifest.json`, the AI jobs table, an estimated AI budget, container details, and any identity/auth gaps or unconfirmed integration shapes flagged along the way. If the owner or usage volume genuinely isn't known yet, say so explicitly and give a labeled estimate rather than leaving it blank or making up a precise-looking number.

## Practical defaults where the reference doc is silent

The master prompt is thorough but leaves a few implementation details genuinely open — not gaps to flag to the platform team, just places where any reasonable choice is compliant and it helps to pick the same one every time so apps built by different people stay consistent. These are suggestions, not rules from §1–12; if a specific app has a good reason to do something else, that's fine.

- **Vault unreachable, or a source in none of granted/pending/denied/missing_required** (this happens right after a failed `/resolve`): show something like "HICO Vault is unreachable right now" — distinct from the §5.1 wording for pending/denied/missing_required, so a user or admin can tell "Vault said no" apart from "we couldn't reach Vault at all."
- **Before calling `ai_invoke` for a given job, check the cached grant state for that source first** (is it in `granted` and not in `missing_required`?) rather than always attempting the call and relying on Vault's own 401/403 to reveal the same thing. It reads more naturally as "the feature disables itself" (§5.1) and doesn't burn a rate-limited request on a call that's already known to fail.
- **Cache `/resolve` with a short TTL (a few seconds to a minute) rather than re-fetching on every hit to `/api/vault/status`.** The doc says "refresh on demand" but doesn't forbid a frontend from polling status every few seconds — without a TTL that turns into continuous hammering of `/resolve`.
- **An app with no local state at all still gets an empty `/data` per §3** (created by the Dockerfile, not by app code) — it just never opens a SQLite connection. Say so plainly in the README rather than leaving it to look like an oversight.
- **A VCA whose entire value is one or two AI actions is allowed to degrade to an empty shell (form present, buttons disabled, banner shown) when AI is denied.** §5.1's "everything else stays fully usable" language reads naturally for apps with an unrelated non-AI feature to fall back to; a pure-AI-utility app doesn't have one, and that's fine — don't invent filler functionality just to have something to degrade to.
- **Route naming:** prefer `/api/actions/<job-name-with-dashes>` (e.g. `/api/actions/draft-reply` for the `draft_reply` job) for anything that triggers an AI job. Not mandated by §3 (which only requires `/api/*`), but keeps routes predictable across apps.
- **If this skill or `references/vca-master-prompt.md` gets updated to a new version, re-run step 4** (recopy the reference doc over each app's `CLAUDE.md`) for any in-flight repos — a `CLAUDE.md` copied from v1.1 doesn't update itself when the live doc reaches v1.2.

## If something doesn't fit this document

Stop and say so rather than improvising around a gap — the reference doc itself says gaps go to the HICO Vault platform team, not to a workaround invented on the spot. This applies to things like a genuinely new kind of external resource, agentic AI, streaming responses, or per-user OAuth (the doc explicitly calls these out as not yet supported).
