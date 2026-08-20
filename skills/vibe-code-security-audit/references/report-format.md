# Audit Report Format

Structure findings like this, ordered Critical → High → Medium → Low. Omit severities with zero findings rather than writing "none found" for every category.

```
## [SEVERITY] Short title of the issue

**Where:** path/to/file.ts:42 (or route/endpoint name if line numbers aren't meaningful)

**What's wrong:** One or two sentences, specific to the actual code, not generic advice.

**Why it matters:** A concrete attack scenario — what could an attacker actually do?
e.g. "An authenticated user can change the `orderId` in the URL to any integer
and view/cancel other users' orders, since GET /api/orders/:id never checks
the order's ownerId against the session user."

**Fix:**
​```ts
// concrete before/after code, not just "add an authorization check"
​```
```

## Summary block at the top

Before the detailed findings, give a short summary: total findings by severity, and the single most urgent thing to fix first. Busy users reading this at 11pm before a launch need the headline before the details.

## Tone

Direct and calm, not alarmist. State severity based on actual exploitability, not worst-case hypotheticals — this keeps the report credible so real critical findings get the attention they deserve.
