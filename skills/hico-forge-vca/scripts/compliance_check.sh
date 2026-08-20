#!/usr/bin/env bash
# HICO Forge VCA compliance self-check (Master Prompt §11).
#
# Usage: compliance_check.sh <repo-root>
#
# Runs the seven greps from §11 against <repo-root>/backend and
# <repo-root>/frontend/src, and prints a PASS/REVIEW verdict for each.
# Exit code is nonzero if any check found something to review, so this can
# also be wired into CI, but the real judgment call (is this hit acceptable?)
# is for whoever runs it to make — this script surfaces hits, it doesn't
# silently decide compliance for you.
set -uo pipefail

REPO="${1:-.}"
BACKEND="$REPO/backend"
FRONTEND_SRC="$REPO/frontend/src"

if [ ! -d "$BACKEND" ]; then
  echo "error: $BACKEND not found — run this from the repo layout described in §3" >&2
  exit 2
fi

EXCL=(--exclude-dir=__pycache__ --exclude-dir=node_modules --exclude-dir=dist \
      --exclude-dir=.venv --exclude-dir=.git --exclude='*.pyc')

FAIL=0

# Comments and docstrings discuss the forbidden things by name - a good VCA says
# "no provider SDK is imported here" in a comment, and that must not read as a
# violation. Compliant code that trips the checker trains people to delete
# honest comments, so drop whole-line comments and docstring-only lines before
# judging. Anything genuinely executable still gets caught.
strip_prose() {
  grep -vE ':[0-9]+:[[:space:]]*(#|//|\*|"""|'"'''"')'
}

check() {
  local num="$1" title="$2"
  shift 2
  echo
  echo "== §11 check $num: $title =="
  local out
  out="$("$@" 2>/dev/null | strip_prose)"
  if [ -z "$out" ]; then
    echo "PASS (no matches in code)"
  else
    echo "REVIEW — matches found:"
    echo "$out"
    FAIL=1
  fi
}

check 1 "no provider SDKs" \
  grep -rniE "${EXCL[@]}" "import (openai|anthropic|litellm|cohere|mistralai)|from (openai|anthropic|litellm)|google\.generativeai" "$BACKEND" "$FRONTEND_SRC"

check 2 "no provider hosts" \
  grep -rniE "${EXCL[@]}" "api\.openai\.com|api\.anthropic\.com|openai\.azure\.com|generativelanguage\.googleapis" "$BACKEND" "$FRONTEND_SRC"

check 3 "no model names (mock model is literally \"mock\")" \
  grep -rniE "${EXCL[@]}" "gpt-[0-9]|claude-|gemini-|llama-" "$BACKEND" "$FRONTEND_SRC"

echo
echo "== §11 check 4: chokepoint integrity (VAULT_* read only inside vault_client.py / vault_mock.py) =="
out="$(grep -rn "${EXCL[@]}" "VAULT_URL\|VAULT_API_KEY\|VAULT_MOCK" "$BACKEND" 2>/dev/null | grep -v "vault_client.py" | grep -v "vault_mock.py" | strip_prose)"
if [ -z "$out" ]; then echo "PASS (no matches in code)"; else echo "REVIEW — matches found:"; echo "$out"; FAIL=1; fi

echo
echo "== §11 check 5: outbound HTTP outside vault_client.py (must map 1:1 to a value-access manifest source) =="
out="$(grep -rn "${EXCL[@]}" "httpx\.\|requests\." "$BACKEND" 2>/dev/null | grep -v "vault_client.py" | strip_prose)"
if [ -z "$out" ]; then
  echo "PASS (no matches in code)"
else
  # Expected for any value-access source's own client. Report which files, so the
  # question is "is each of these a declared source?" rather than a wall of lines.
  echo "REVIEW — outbound HTTP in these files; each must map 1:1 to a manifest source:"
  echo "$out" | sed 's/:[0-9]*:.*//' | sort -u | sed 's/^/  /'
  echo "  (run with -v for the matching lines)"
  [ "${2:-}" = "-v" ] && echo "$out"
  FAIL=1
fi

check 6 "secrets scan (review every hit; only obvious test fixtures are acceptable)" \
  grep -rniE "${EXCL[@]}" "(api_key|apikey|secret|password|token)\s*[:=]\s*['\"][^'\"]{8,}" "$BACKEND" "$FRONTEND_SRC"

# Check 7 targets the app OWNING authentication, not the app knowing who is
# acting. Borrowing identity from Forge is the sanctioned pattern, so the
# vocabulary of that pattern is excluded here on purpose - otherwise the check
# fires on compliant code and teaches people to rename things to dodge a grep,
# which is strictly worse than the grep not existing.
check 7 "no app-owned authentication (§1 rule 7 - owning identity, not knowing the user)" \
  grep -rniE "${EXCL[@]}" "password_hash|bcrypt|passlib|argon2|scrypt|session_cookie|set_cookie|jwt\.|jsonwebtoken|oauth2_password|login_required|CREATE TABLE users|def (login|signup|register)\b" "$BACKEND" "$FRONTEND_SRC"

# ---------------------------------------------------------------------------
# Security checks (8-12).
#
# §11 proves the app borrows credentials and AI correctly. It says nothing about
# whether the app is injectable, whether a stray request can trigger something
# destructive, or whether it leaks a secret down an error path - and compliance
# is not security. These five come from HICO's vibe-code security audit, kept to
# the patterns worth failing a build over.
#
# Deliberately NOT a full audit. The rest needs judgement and a call path, which
# is what the `vibe-code-security-audit` skill is for; read its findings through
# references/security-audit-for-vcas.md, because a generic audit judges a VCA
# against the wrong model on the very first category.
# ---------------------------------------------------------------------------

check 8 "no injection into a live system (build queries and commands from parameters, never strings)" \
  grep -rniE "${EXCL[@]}" "execute\(\s*(f[\"']|[\"'][^\"']*[\"']\s*[+%])|executemany\(\s*f[\"']|os\.system\(|shell\s*=\s*True|\beval\(|\bexec\(" "$BACKEND"

check 9 "no unescaped user content rendered as HTML (XSS)" \
  grep -rniE "${EXCL[@]}" "dangerouslySetInnerHTML|innerHTML\s*=|outerHTML\s*=|v-html|document\.write\(" "$FRONTEND_SRC"

# Mass assignment is the one §2 finding that applies to a VCA unchanged: there is
# no per-user identity to bypass, but a handler that splats a request body into a
# model still lets a caller set fields the app never meant to expose.
check 10 "no mass assignment (allowlist the fields a handler accepts)" \
  grep -rniE "${EXCL[@]}" "\*\*(request|req|body|payload)\.(json|data|body|dict)|\.update\((request|req|body)\b|Object\.assign\(" "$BACKEND"

# A VCA has no app-level auth, so every endpoint is reachable by anyone who can
# reach the container. A permissive CORS policy on top of that hands the same
# access to any web page a colleague happens to open.
check 11 "no wildcard CORS (every endpoint is already unauthenticated)" \
  grep -rniE "${EXCL[@]}" "allow_origins\s*=\s*\[?\s*[\"']\*|Access-Control-Allow-Origin[\"']?\s*[:,]\s*[\"']\*|allow_origin_regex\s*=\s*[\"']\.\*" "$BACKEND"

# The app holds a Vault key and, for value-access sources, live third-party
# credentials. Error paths are where those escape even when the happy path is
# clean, so this looks for them reaching a log line or a response.
# The logger is matched as "any identifier containing log", not "logger?" - the
# obvious spelling misses the commonest one. `logger?\.` matches "logge" plus an
# optional "r", so it catches logger. and never log., which is what most code
# actually writes. Verified against a fixture that logs its own API key.
check 12 "no secrets in logs or responses (§6, §8 - resolved values live in memory only)" \
  grep -rniE "${EXCL[@]}" "(print|[A-Za-z_]*log[A-Za-z_]*\.(debug|info|warn|warning|error|exception|critical))\(.*(api_key|apikey|api_token|secret|password|token|resolved|granted)" "$BACKEND"

echo
echo "== not grep-able - check these by hand =="
echo "  * Scope: can the app write outside what the admin granted? Take every endpoint"
echo "    that accepts an identifier (project key, table id, path, folder) and ask what"
echo "    happens when it names something ungranted. The refusal must come from the"
echo "    app's own code, not from hoping the upstream system says no."
echo "  * Per-person data: a VCA runs on a shared team identity, so everyone using it"
echo "    sees everything it can see. If it holds anything belonging to one person,"
echo "    that is a design finding for the platform team - not something to fix with a"
echo "    login (forbidden) or a 'who are you' dropdown (a login without a password)."
echo "  * Dependencies: run this repo's own audit tool - pip-audit, npm audit - and"
echo "    check the frontend build too. Nothing above looks at your dependencies."
echo "  * Destructive endpoints: anything that writes to a live system is one"
echo "    unauthenticated request away from anyone on the network."

echo
if [ "$FAIL" -eq 0 ]; then
  echo "All 12 checks passed with no matches. That is not the same as secure -"
  echo "the hand-checked items above and a real audit still apply."
else
  echo "One or more checks found matches that need human review (see above)."
  echo "A match is not automatically a violation — e.g. check 5 is fine if every hit is inside vault_client.py's own httpx calls, or a value-access source's client using its declared manifest fields. Confirm each hit against the relevant §11 checklist item, or for checks 8-12 against references/security-audit-for-vcas.md."
fi
exit "$FAIL"
