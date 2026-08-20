---
name: vibe-code-security-audit
description: Use this skill whenever the user wants a security audit, vulnerability review, or "security check" of a codebase — especially AI-generated / "vibe coded" SaaS apps that were built quickly without a security-first process. Trigger on requests like "check my app for vulnerabilities", "audit my auth system", "is my code secure", "review this before I ship it", or any mention of JWT/OAuth/password hashing/user management security. Also trigger for recurring/scheduled security reviews of a repo. Covers authentication, authorization (especially IDOR/BOLA), input validation/injection, API security, secrets management, data protection, dependency vulnerabilities, and logging. Produces a prioritized, actionable findings report, not just a generic checklist — always ground findings in the actual code, with file/line references and concrete fixes.
---

# Vibe Code Security Audit

A repeatable procedure for auditing AI-assisted/"vibe coded" SaaS applications for common, high-impact security vulnerabilities. Vibe-coded apps tend to share a predictable failure pattern: they work correctly along the "happy path" but skip the checks a security-conscious engineer would add by default. This skill exists to catch those gaps systematically, every time, rather than relying on memory or a one-off gut check.

## First: is this a HICO Forge VCA?

Check for a `manifest.json` with a `sources` array, a `backend/vault_client.py`,
or a `CLAUDE.md` containing the VCA Master Prompt. If any of those are present,
**read `hico-forge-vca/references/security-audit-for-vcas.md` before reporting
anything.**

A VCA deliberately owns no authentication — no login, no user table, no password
handling, no sessions. So §1 of the checklist below inverts: finding bcrypt or a
JWT library in a VCA is not "good password hygiene", it is a **compliance
failure whose fix is deleting the code**, not hardening it. Recommending bcrypt
there sends the developer off to build a login system that gets their app
rejected at registration.

Two findings the generic checklist cannot express also matter more than anything
in §1 for these apps: whether the app can act outside what the admin granted (the
VCA form of BOLA), and whether it holds per-person data it has no way to separate
on a shared team identity. Both are in that reference file.

For any app that is *not* a VCA, ignore this section and proceed normally.

## When to run a full audit vs. a targeted check

- **Full audit**: user asks to review/audit/check "the app", "the backend", "before I launch", or gives no specific scope. Run through every category below.
- **Targeted check**: user names a specific area ("check my JWT setup", "review the password reset flow"). Jump straight to the matching category in `references/checklist.md`, but still do a quick pass for the most common cross-cutting issue (IDOR/BOLA — see below) since it's the single most frequent vibe-coding vulnerability and often hides in unrelated endpoints.

## Procedure

1. **Locate the code.** If a repo/folder is available, use `bash_tool`/`view` to explore it — don't ask the user to paste code if you can read it directly. Identify the stack (framework, DB, auth library) first; this determines which specific checks in `references/checklist.md` apply.

2. **Read `references/checklist.md`** for the full category-by-category checklist (auth, authorization, input validation, API security, secrets, data protection, dependencies, logging). It contains concrete code patterns to grep for and what "good" vs "bad" looks like per category.

3. **Search systematically, don't just skim.** Use targeted greps/searches for known bad patterns before reading files top to bottom — this catches issues faster than manual review and won't miss instances across a large codebase. Examples: string-concatenated SQL, `alg: none` or missing JWT verification, hardcoded secrets, endpoints missing auth middleware, password hashing calls. See `references/checklist.md` for the specific patterns per category.

4. **For every finding, verify it's real** by reading the surrounding code/call path — don't report a pattern match as a vulnerability without confirming it's actually reachable and unmitigated elsewhere (e.g., a raw SQL string that's actually parameterized further down, or an endpoint that has auth middleware applied globally rather than per-route).

5. **Prioritize findings by severity and exploitability**, not by category order:
   - **Critical**: auth bypass, IDOR/BOLA on sensitive data, hardcoded prod secrets, SQL injection, privilege escalation.
   - **High**: weak password hashing, missing rate limiting on auth endpoints, broken CORS, mass assignment.
   - **Medium**: missing security headers, verbose error leakage, outdated dependencies with known CVEs.
   - **Low**: hardening/best-practice items with limited real-world exploitability.

6. **Report findings** in the format in `references/report-format.md`: what's wrong, exactly where (file/line), why it matters (concrete attack scenario, not just "this is bad practice"), and a specific fix (code-level, not just "add validation"). Do not pad the report with items that don't apply to this stack — a report full of theoretical/non-applicable items trains the user to skim past real findings.

7. **Offer to fix.** After presenting findings, offer to implement the fixes directly (highest severity first) rather than just leaving the user with a list.

## Regular/recurring audits

If the user wants this run repeatedly (e.g., before every deploy, weekly), suggest they keep a running `SECURITY_AUDIT.md` in the repo noting what's been checked and when, so each new audit can focus on *diffs* since the last one plus a quick full pass on the critical-severity categories (auth, authorization, injection) which are cheap to re-check and highest-consequence if regressed.

## Key principle: don't just hand back the checklist

The checklist in `references/checklist.md` is Claude's internal tool for knowing what to look for — it is not the deliverable. The user needs a report grounded in *their actual code*, not a repeat of generic security advice they could get anywhere. If no code is available to inspect, say so and ask for the repo/path rather than producing a generic checklist as if it were an audit.
