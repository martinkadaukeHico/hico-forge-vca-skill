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

check() {
  local num="$1" title="$2"
  shift 2
  echo
  echo "== §11 check $num: $title =="
  local out
  out="$("$@" 2>/dev/null)"
  if [ -z "$out" ]; then
    echo "PASS (no matches)"
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
out="$(grep -rn "${EXCL[@]}" "VAULT_URL\|VAULT_API_KEY\|VAULT_MOCK" "$BACKEND" 2>/dev/null | grep -v "vault_client.py" | grep -v "vault_mock.py")"
if [ -z "$out" ]; then echo "PASS (no matches)"; else echo "REVIEW — matches found:"; echo "$out"; FAIL=1; fi

echo
echo "== §11 check 5: outbound HTTP outside vault_client.py (must map 1:1 to a value-access manifest source) =="
out="$(grep -rn "${EXCL[@]}" "httpx\.\|requests\." "$BACKEND" 2>/dev/null | grep -v "vault_client.py")"
if [ -z "$out" ]; then echo "PASS (no matches)"; else echo "REVIEW — matches found (confirm each maps to manifest.json):"; echo "$out"; FAIL=1; fi

check 6 "secrets scan (review every hit; only obvious test fixtures are acceptable)" \
  grep -rniE "${EXCL[@]}" "(api_key|apikey|secret|password|token)\s*[:=]\s*['\"][^'\"]{8,}" "$BACKEND" "$FRONTEND_SRC"

check 7 "no app-owned authentication (§1 rule 7)" \
  grep -rniE "${EXCL[@]}" "login|password_hash|bcrypt|passlib|session_cookie|jwt" "$BACKEND" "$FRONTEND_SRC"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "All 7 checks passed with no matches."
else
  echo "One or more checks found matches that need human review (see above)."
  echo "A match is not automatically a violation — e.g. check 5 is fine if every hit is inside vault_client.py's own httpx calls, or a value-access source's client using its declared manifest fields. Confirm each hit against the relevant §11 checklist item."
fi
exit "$FAIL"
