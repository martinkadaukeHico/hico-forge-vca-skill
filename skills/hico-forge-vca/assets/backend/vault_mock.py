"""Canned Vault responses for VAULT_MOCK=1. Dev only — vault_client refuses prod.

Keep in sync with manifest.json: every source there should appear granted here
by default. VAULT_MOCK_PENDING / _DENIED / _MISSING move sources out of
`granted` so the §5.1 degraded UI states are testable offline. No real values
in this file, ever.

EDIT THIS FILE PER APP: update _GRANTED to match your manifest.json sources
exactly (same keys, same shape as the real /resolve response for each access
type). The ai_invoke() body below is generic and rarely needs changes, except
to add job-aware canned answers for closed-set (§5.4) classification jobs.
"""
import os

# Every source in manifest.json, granted. Shapes must match §5.1 exactly.
# Replace/extend this with your app's real sources.
_GRANTED = {
    "ai": {"access": "proxy", "proxy_url": "/api/v1/broker/ai/invoke"},
    # Example `value`-access source — delete or replace with your real ones:
    # "crm": {"access": "value", "url": "http://localhost:9",
    #         "db": "mock", "username": "mock", "api_key": "mock"},
}


def _keys(var: str) -> list[str]:
    return [k.strip() for k in os.environ.get(var, "").split(",") if k.strip()]


def resolve() -> dict:
    pending, denied = _keys("VAULT_MOCK_PENDING"), _keys("VAULT_MOCK_DENIED")
    missing = _keys("VAULT_MOCK_MISSING")          # "source.field" entries
    withheld = set(pending) | set(denied)
    return {
        "app": "myapp",
        "granted": {k: v for k, v in _GRANTED.items() if k not in withheld},
        "denied": denied,
        "pending": pending,
        "missing_required": missing,
    }


def ai_invoke(job: str, messages: list[dict]) -> dict:
    last = messages[-1]["content"] if messages else ""
    # May be job-aware (§7 rule 6) — e.g. return a valid closed-set label for a
    # §5.4 classification job so the app's parse path is exercisable offline.
    # If this app has closed-set jobs, add a branch here that returns the bare
    # label (no [MOCK:] prefix) for those job names specifically.
    return {
        "content": f"[MOCK:{job}] canned answer for: {last[:80]}",
        "model": "mock", "input_tokens": 0, "output_tokens": 0,
        "points_charged": None,
    }
