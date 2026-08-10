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
   - Does it need to know *which person* is acting (per-user data, approvals, an audit trail naming people)? Read §1 rule 7 carefully, because it conflates two different things. **"The app must not OWN identity" is a permanent rule.** "No identity is available to the app" is a temporary fact about today's platform. So: never build a login screen, a user table, password handling, or role storage — that stays absolutely forbidden. But *borrowing* who-is-acting from Forge, the same way the app already borrows AI and credentials, is the sanctioned direction. Until Forge ships identity lending, build the seam and run on a shared team context with a visible banner saying so — see "The identity seam" below. Flag the limitation to the user; don't quietly design around it either by faking a login or by pretending the app never needs to know.
   - Does it depend on anything that only exists on someone's desktop (local Outlook, local files, a USB device, a locally-installed CLI)? Device-local resources don't exist in Forge (§2) — flag it and propose a server-side equivalent, or say the idea isn't Forge-compatible as described.
   - Does it want the model to browse, search, or take actions ("agentic" AI)? The broker is plain chat completions only (§5.3) — flag it rather than faking it with loops of completions. **This is narrower than it first reads, and reading it too broadly is the more common mistake.** What is forbidden is a loop in which *the model* decides what to do next. What is positively encouraged is deterministic orchestration *around* single completions: your code gathers the context, calls the broker once, parses the reply, applies the result, and decides in code whether another call is warranted. A feature that makes twenty completions is perfectly compliant if your code chose all twenty. If you find yourself thinking "any multi-step AI feature is banned, so I'll either give up or quietly build an agent" — both of those are wrong. Write the loop in Python.
   - Does it need a live external system (CRM, mailbox, another API)? You'll need that *system's real API docs* before writing the client for it (§4) — ask the user for them rather than guessing at endpoints and payload shapes. A guessed integration looks done and is actually broken.
   If the idea conflicts with a rule, say so and propose a compliant alternative out loud — never quietly build the noncompliant version because it's easier or the user didn't ask about Vault specifically.
3. **Scaffold the repo per §3's layout.** Copy the reference implementations in `assets/backend/` into the new repo's `backend/` directory as your starting point rather than writing `vault_client.py` and `vault_mock.py` from scratch — they already encode the retry/error/status-code rules from §5.2 and §6 correctly, including the easy-to-get-wrong bits (retry once on 502 and never on 429, `VaultConfigError` vs. plain `VaultError`, mock refusing to start in prod). Adapt `assets/backend/ai_jobs.py` and `assets/manifest.example.json` to the app's actual jobs and sources — don't ship the placeholders as-is.
4. **Write `CLAUDE.md` in the new repo's root as a byte-for-byte copy of `references/vca-master-prompt.md`.** This is what makes the rules durable across sessions: the next time Claude Code (yours or a colleague's) opens this repo, it reads `CLAUDE.md` automatically and inherits the same constraints, even without this skill triggering again. **Copy it verbatim — do not summarise it, do not replace its inline code listings with pointers to this skill's `assets/`.** The new repo does not contain this skill, so a pointer to `assets/backend/vault_client.py` is a dangling reference for everyone who opens that repo later. `references/vca-master-prompt.md` is kept identical to the platform team's `vault/docs/forge-vca-master-prompt.md` precisely so this copy is safe.
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

## Patterns that keep coming up

These are the recipes a compliant VCA needs over and over. They are not in the master prompt — it says *what* the rules are, not how to satisfy them in practice. Reach for these before inventing your own; `hico-pmo` (see "Reference implementation") is a working example of every one.

### Never let the model report its own work

The single most common request is "have the AI change this, and show me what it changed." Do **not** ask the model to describe its edits — it will sometimes claim a change it didn't make, or miss one it did, and the user has no way to tell.

Keep two copies of the data: `baseline` (exactly what the external system last told you) and `working` (baseline + AI proposals + human edits). Compute the difference in code, and highlight *that*. The model supplies content; your code decides what counts as a change. It then cannot lie about it, because it was never asked.

The same shape covers "review before it goes live": all edits land in `working`, the external system is untouched until a human presses Commit, and every drag or AI suggestion is therefore reversible for free.

### "Do this across everything" without an agent loop

The request that most often gets mistaken for needing an agent is a bulk one: *"every ticket about X needs Y"*, *"reply to all the unanswered ones"*, *"tidy up the stale entries"*. It feels agentic because the model appears to be choosing what to act on.

It isn't. Split it into two ordinary completions with your code in charge of both:

1. **Ask once what the instruction is about.** Give the model the candidate list and require an answer drawn from it — `item: <ID>` lines, IDs only, no prose. This is a closed set (§5.4): the candidates *are* the allowed vocabulary.
2. **Validate that answer against reality.** An ID the model invented gets dropped, never fuzzy-matched onto something that looks similar — matching a hallucinated ID to a real record is how a bulk action quietly hits the wrong thing.
3. **Cap how many items one instruction may touch**, and *say so* when the cap bites. The cap is not protection against the model; it's protection against a human typing something vague and rewriting half a dataset in one click. Silent truncation reads as "it did everything."
4. **Run your existing single-item job on each survivor**, collecting per-item outcomes.

The model answered one bounded question. Your code decided the rest. That's compliant, and it's also just better — you can log which items were selected and why, which no agent loop gives you.

The same skeleton covers "which of these does the user mean?" generally. Whenever you're tempted to let the model drive a sequence, ask what single question you'd need answered to drive it yourself.

### Getting structured data out of a plain-completion broker

There is no JSON mode and no function calling (§5.3). Use §5.4: ask for fixed `key: value` lines, one per line, and parse defensively — ignore unknown keys, treat a missing key as "human must fill this in", allow a key to repeat where you want a list. This degrades far better than JSON, which fails wholesale the moment the model wraps it in prose or a code fence.

For anything with a fixed set of answers (a category, a severity, a yes/no), define the closed set in your `ai_jobs.py`, ask for exactly one word, and match it exactly. Anything else becomes an explicit `unknown` that the UI shows as needs-review. **Never** map an unrecognised answer onto your best guess, and never retry in a loop hoping for a compliant answer.

### The mock stands in for the system, never for Vault's decision

A subtle one that is easy to get backwards and hard to notice. When you build the factory that returns a client for a source, it is natural to write:

```python
if mock:
    return MockThing()          # WRONG ORDER
if not granted.get("thing"):
    return None
```

That makes `VAULT_MOCK_DENIED=thing` hand back a perfectly working client, because mock short-circuits before the grant is ever consulted — so the §5.1 degraded state is unreachable offline, which is exactly what §7 rule 4 exists to prevent. Check the grant **first**, then decide whether the client is real or mocked.

The same mistake in a different costume: gating a feature on *"did I manage to build a client?"* instead of on *the source's state*. A source can be in `granted` **and** in `missing_required` at the same time — granted in principle, unusable in practice because the admin has not filled a required field. A client-only check sails straight past that and fails later with a confusing upstream error instead of showing "Awaiting configuration in HICO Vault".

Both bugs are invisible to code review and obvious the moment you actually run the app with the degraded env vars set. Which is why §11 says to run them.

### Make the mock prove something

§7 mock mode is not decoration — it is how the app gets built and demoed before anyone registers it in Forge. A mock that always returns the same canned string will pass a click-through and hide every real bug.

Make canned answers *about the input*: read the `key: value` lines your own prompt put into the message and echo them back. Make the mock exercise the interesting branches — if you have a closed-set classifier, the mock should be able to return each label, not just the happy one. If the external system can legitimately refuse something (a workflow that forbids a status change, a validation error), make the mock refuse it too, so the error path is exercisable offline. Note the one exception in §7 rule 5: closed-set replies must be the **bare** label, with no `[MOCK]` prefix, or your own exact-match parser fails on every mocked classification.

### Surface partial failure, always

When you push several changes to an external system, some can succeed and some can fail. Return and display the outcome **per item**. A UI that says "committed" while one card was silently refused is worse than one that fails loudly — the user walks away believing something happened that didn't.

Related: when you re-sync local state after a partial commit, do it per item too. Re-baseline what landed and leave what failed marked as outstanding. All-or-nothing re-baselining either re-sends work the system already accepted, or leaves accepted work looking uncommitted forever.

### Idempotency, when a link can be opened twice

If a workflow mails or posts a link into your app, assume it will be clicked repeatedly, by several people, days apart. Anything the app does on arrival must be safe to do twice.

Watch for state that lives in the wrong place: if you track "already handled" only in data pulled from the external system, a fresh pull wipes it and the work repeats. Keep that record in the app's own `/data` store, keyed by the source record's id, and write it only once the external system has actually accepted the result.

### The identity seam

Until Forge lends identity, put a single `backend/identity.py` chokepoint in front of "who is acting", have it return a shared team context, and show a banner saying exactly that and why. Every feature that will one day be per-user calls that one function. When Forge ships identity lending, one file changes.

Do not scatter `current_user()`-ish logic through the app, and do not skip the banner — a shared context presented as if it were a real user is the dishonest version of this.

## Practical defaults where the reference doc is silent

The master prompt is thorough but leaves a few implementation details genuinely open — not gaps to flag to the platform team, just places where any reasonable choice is compliant and it helps to pick the same one every time so apps built by different people stay consistent. These are suggestions, not rules from §1–12; if a specific app has a good reason to do something else, that's fine.

- **Vault unreachable, or a source in none of granted/pending/denied/missing_required** (this happens right after a failed `/resolve`): show something like "HICO Vault is unreachable right now" — distinct from the §5.1 wording for pending/denied/missing_required, so a user or admin can tell "Vault said no" apart from "we couldn't reach Vault at all."
- **Before calling `ai_invoke` for a given job, check the cached grant state for that source first** (is it in `granted` and not in `missing_required`?) rather than always attempting the call and relying on Vault's own 401/403 to reveal the same thing. It reads more naturally as "the feature disables itself" (§5.1) and doesn't burn a rate-limited request on a call that's already known to fail.
- **Cache `/resolve` with a short TTL (a few seconds to a minute) rather than re-fetching on every hit to `/api/vault/status`.** The doc says "refresh on demand" but doesn't forbid a frontend from polling status every few seconds — without a TTL that turns into continuous hammering of `/resolve`.
- **An app with no local state at all still gets an empty `/data` per §3** (created by the Dockerfile, not by app code) — it just never opens a SQLite connection. Say so plainly in the README rather than leaving it to look like an oversight.
- **A VCA whose entire value is one or two AI actions is allowed to degrade to an empty shell (form present, buttons disabled, banner shown) when AI is denied.** §5.1's "everything else stays fully usable" language reads naturally for apps with an unrelated non-AI feature to fall back to; a pure-AI-utility app doesn't have one, and that's fine — don't invent filler functionality just to have something to degrade to.
- **Route naming:** prefer `/api/actions/<job-name-with-dashes>` (e.g. `/api/actions/draft-reply` for the `draft_reply` job) for anything that triggers an AI job. Not mandated by §3 (which only requires `/api/*`), but keeps routes predictable across apps.
- **If this skill or `references/vca-master-prompt.md` gets updated to a new version, re-run step 4** (recopy the reference doc over each app's `CLAUDE.md`) for any in-flight repos — a `CLAUDE.md` copied from v1.1 doesn't update itself when the live doc reaches v1.2.

## Reference implementation

`hico-pmo` (Martin Kadauke's PMO app) is the first app built against these rules from the first commit. It is worth reading when a rule is clear but its application isn't: it has a real external-system client written from published API docs, the baseline/working diff pattern, closed-set parsing with an explicit unknown state, per-item commit outcomes including upstream refusals, a mock that exercises the failure branches, and the identity seam running in shared-context mode with the banner.

It is a reference, not scripture — it also carries a `docs/PLATFORM-TODOS.md` listing where it is deliberately incomplete because the platform isn't there yet. Copying that habit is more useful than copying any particular file: when you build against a capability Forge doesn't have, write down the seam, the assumption, and who owns closing it.

## Testing against a real system before the app is registered

Every VCA hits this wall in its first week: the mock proves the UI, but it cannot prove that your Jira/Odoo/CRM request shapes are right, and §11 explicitly asks whether they are. Meanwhile §10 forbids "a local fallback that works without Vault", and Vault has not issued the app a key yet. Read strictly, there is no way to ever make the first real call.

**Do not resolve this by pasting a credential into the app.** Not into `vault_mock.py`, not into `.env`, not into an env var — that is precisely the secret-smuggling path this platform exists to close, and an app that ever worked that way tends to keep a quiet code path that still does.

**The sanctioned route is to ask for a scoped dev grant, in-band.** The app requests it; a Vault admin approves it in Forge; Vault issues a short-lived key limited to what was asked for. The request is made from the app so it carries the app's own manifest and identity, and so the trail lives where every other grant decision lives.

What the request must carry, because an admin cannot approve what they cannot evaluate:

- **which source** and **which operations** — read-only, or writes too
- **the blast radius**: the specific project / board / mailbox / dataset it may touch, never "Jira"
- **why**, in a sentence a non-developer can judge: what is being built and what the mock cannot prove
- **how long** — dev grants expire; a grant with no end date is a permanent grant with extra steps
- **a proposed slot to talk it through**, so approval is a conversation when it needs to be and one click when it does not

Then, while you wait — and this is the part people skip — **keep building against the mock**. A dev grant is for verifying request shapes, not for developing against. If the feature only works once the real system is wired, the mock was too thin (see "Make the mock prove something").

Two rules that stay true even with a dev grant in hand:

- **Scope writes in the app as well.** A grant that permits writing to one project should be matched by an allowlist in the code, checked at the last line before the request is built. Approval and enforcement are different things, and the one that saves you is the one nearest the HTTP call.
- **Mark anything the app generates** so it can be swept up — a title prefix, a label, whatever the system supports. Apply it on update as well as create, or the first AI-rewritten title quietly loses it.

Until Forge ships this, whatever you do instead is a **deviation**: keep it in one file, keep it out of git, have `/api/vault/status` report it so the UI cannot claim mock mode while talking to a live system, and write it down as a platform TODO. `hico-pmo` does exactly that — see its `docs/PLATFORM-TODOS.md` F-7 for the shape and for the request contract being proposed to the platform team.

## Proposed extensions not yet in the master prompt

These came out of building `hico-pmo` and are **not** v1.1 rules. If your app needs one, follow the pattern below and flag it to the platform team rather than assuming it is sanctioned.

**Do not put a proposed extension in a shipped `manifest.json`.** The manifest is ingested by Forge and validated against the v1.1 schema; an invented `access` value or `kind` makes the whole file unregisterable, and the failure surfaces at the worst possible moment — when the admin is trying to register your app. Keep proposals in `docs/PLATFORM-TODOS.md` and declare only what the schema allows. This bites harder than it sounds, because §4 also says the manifest must describe **the app you actually built**: a source you have not written code for yet should not be in there at all, whatever its `access` mode. Declaring it early just asks the admin to enter credentials for something that does not exist.

- **`access: value_user`** — a source whose values are stored per user in their own Vault profile (e.g. each consultant's own Odoo API key) rather than once by the admin. The admin grants the *capability*; each user supplies their own *values*. This is not the same as `oauth_delegated`, which is per-user consent to a third-party OAuth flow; this is a per-user stored secret. Depends on identity lending, so it resolves `pending` today and every feature using it must disable itself. If you use it: never cache a resolved per-user value under a key that isn't scoped to that user.
- **Identity introspection** — see "The identity seam" above. Build the seam now, consume the capability when it exists.
- **Brokered outbound mail and click-tracked links** — several PMO-ish apps will want "email someone a link and record whether they opened it." Declaring SMTP as a `value` source works but puts mail credentials in an app, which is against the spirit of rule 1. A Vault mail broker (like the AI broker) is the better answer. Until that's decided, say which you did and why.

## If something doesn't fit this document

Stop and say so rather than improvising around a gap — the reference doc itself says gaps go to the HICO Vault platform team, not to a workaround invented on the spot. This applies to things like a genuinely new kind of external resource, agentic AI, streaming responses, or per-user OAuth (the doc explicitly calls these out as not yet supported).
