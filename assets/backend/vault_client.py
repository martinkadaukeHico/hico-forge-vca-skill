"""Single chokepoint to HICO Vault — the ONLY module that talks to Vault.

Rules enforced here and nowhere else:
- config from env only: VAULT_URL, VAULT_API_KEY
- VAULT_MOCK=1 -> canned responses from vault_mock.py (dev only, refuses in prod)
No other module may read VAULT_* environment variables.

Adapt names to your app (e.g. the "backend" package path), but keep this
structure and these behaviors intact — they exist to satisfy the HICO Forge
VCA Master Prompt §6. Every other module gets Vault data only by importing
this one.
"""
import os
import time

import httpx


class VaultError(RuntimeError):
    """Any Vault-side failure; message is safe for logs and UI.

    `status_code` is Vault's HTTP status when a response came back, or None when
    Vault was unreachable. Callers branch on it to implement the §5.2 table —
    never parse the message string.
    """

    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


class VaultConfigError(VaultError):
    """Vault is not configured at all — a deployment error, not a runtime one.
    This is the only Vault failure that may stop the app booting (§1 rule 6)."""


def mock_enabled() -> bool:
    on = os.environ.get("VAULT_MOCK", "").lower() in ("1", "true", "yes")
    if on and os.environ.get("APP_ENV", "dev") == "prod":
        raise RuntimeError("VAULT_MOCK must never be enabled in prod")
    return on


def _config() -> tuple[str, str]:
    url = os.environ.get("VAULT_URL")
    key = os.environ.get("VAULT_API_KEY")
    if not url or not key:
        raise VaultConfigError("Vault not configured: set VAULT_URL and VAULT_API_KEY")
    return url.rstrip("/"), key


def check_configured() -> None:
    """Call once at startup: raises VaultConfigError -> the app must not boot.

    Deliberately does NOT contact Vault. An unreachable Vault must leave the app
    running so /api/vault/status can report `vault: unreachable` (§1 rule 6, §8).
    """
    if not mock_enabled():
        _config()


def resolve() -> dict:
    """Granted resource config. Call at startup, cache in memory only."""
    if mock_enabled():
        from backend import vault_mock
        return vault_mock.resolve()
    url, key = _config()
    try:
        resp = httpx.get(f"{url}/api/v1/resolve",
                         headers={"Authorization": f"Bearer {key}"}, timeout=15.0)
    except httpx.HTTPError as e:
        raise VaultError(f"Vault unreachable: {e}") from e
    if resp.status_code >= 400:
        raise VaultError(f"Vault {resp.status_code}: {resp.text[:300]}", resp.status_code)
    return resp.json()


def ai_invoke(job: str, messages: list[dict], max_output_tokens: int = 2048) -> dict:
    """Run one AI job through Vault.
    Returns {content, model, input_tokens, output_tokens, points_charged}.

    Retries exactly once on 502 (upstream provider failure, §5.2). Every other
    status is raised straight to the caller with `status_code` set — no retry.
    """
    if mock_enabled():
        from backend import vault_mock
        return vault_mock.ai_invoke(job, messages)
    url, key = _config()
    payload = {"job": job, "messages": messages,
               "max_output_tokens": max_output_tokens}
    for attempt in (1, 2):
        try:
            resp = httpx.post(
                f"{url}/api/v1/broker/ai/invoke",
                headers={"Authorization": f"Bearer {key}"},
                json=payload,
                timeout=60.0,
            )
        except httpx.HTTPError as e:
            raise VaultError(f"Vault unreachable: {e}") from e
        if resp.status_code == 502 and attempt == 1:
            time.sleep(1.5)   # the one sanctioned retry; 429 must NEVER be retried
            continue
        if resp.status_code >= 400:
            raise VaultError(f"Vault {resp.status_code}: {resp.text[:300]}",
                             resp.status_code)
        return resp.json()
