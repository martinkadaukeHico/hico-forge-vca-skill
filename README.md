# HICO Group Skills — Claude Code plugin

Two skills, meant to be used together.

**`hico-forge-vca`** — loads itself whenever someone at HICO starts building an
internal web app, tool, dashboard or prototype with Claude Code, including when
the request never mentions Forge, Vault or VCA by name. Apps built without these
rules have to be rewritten before they can run on the platform. HICO has already
done that migration once; this is how we avoid doing it again.

**`vibe-code-security-audit`** — audits an app for real vulnerabilities before it
ships: injection, broken authorization, secrets, dependency CVEs. Written by
HICO's security expert for AI-assisted apps generally, so it works on anything,
not only Forge apps.

**Compliance and security are not the same thing**, which is why both are here.
The Forge rules prove an app borrows credentials and AI correctly; they say
nothing about whether it is injectable. The audit catches that — but a generic
audit judges a Forge app against the wrong model and gets its first category
backwards, recommending bcrypt for an app that must not have passwords at all.
`skills/hico-forge-vca/references/security-audit-for-vcas.md` reconciles the two,
and the Forge skill routes through it automatically.

This repo is both the **plugin** and its **marketplace**, so there is one URL to
configure and nothing to host.

---

## For the Claude admin: enable it for everyone

Go to **claude.ai → Admin Settings → Claude Code → Managed settings** and add
these two keys to the JSON (merge them into what is already there — do not
replace the whole document):

```json
{
  "extraKnownMarketplaces": {
    "hico": {
      "source": {
        "source": "github",
        "repo": "martinkadaukeHico/hico-forge-vca-skill"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": [
    { "id": "hico-skills@hico" }
  ]
}
```

That is the whole change.

- `extraKnownMarketplaces` registers this repo as a source. `hico` is just the
  local name for it and is referenced by the `@hico` suffix below.
- `enabledPlugins` switches it on for everyone, so nobody has to install
  anything by hand.
- `autoUpdate: true` means people pick up new versions without being asked.

Managed settings are fetched at Claude Code startup and roughly hourly after
that, and cached in `~/.claude/remote-settings.json`. Expect it to appear within
the hour, or immediately on the next restart.

### Two things to check first

**The repo must be reachable by the people using it.** If
`martinkadaukeHico/hico-forge-vca-skill` is private, every user's machine needs
credentials for it — an SSH key, or a token configured with
`git config --global url."https://<PAT>@github.com/".insteadOf "https://github.com/"`.
If that is awkward, making the repo public is the simpler answer: it contains no
secrets, only conventions. Worth a look before rollout either way, since a
private repo without credentials fails silently per-user rather than loudly for
the admin.

**Managed settings only reach org-authenticated users.** Anyone signed in with a
personal Claude account, a Console API key outside the org, or running through
Bedrock/Vertex will not receive them. Those users can install it themselves — see
below — or you can deploy the same JSON as a file per machine
(`/etc/claude-code/managed-settings.json` on Linux/WSL,
`C:\Program Files\ClaudeCode\managed-settings.json` on Windows,
`/Library/Application Support/ClaudeCode/managed-settings.json` on macOS).

---

## For an individual, without the admin

```
/plugin marketplace add martinkadaukeHico/hico-forge-vca-skill
/plugin install hico-skills@hico-forge-vca-skill
```

Or, without the plugin system at all, copy the skill folder straight in:

```
cp -r skills/hico-forge-vca ~/.claude/skills/
```

The skill is self-contained — SKILL.md plus its own references, assets and
script — so the plain copy works identically. It just will not update itself.

---

## Verifying it is on

```
/plugin list
```

should show `hico-skills`. The skill announces itself when it triggers; it should
fire on something like *"help me build a small internal dashboard for the sales
team"* without Forge being mentioned. If it does not trigger, that is a bug in
the skill's description — please report it rather than working around it.

---

## What is in here

```
.claude-plugin/
  plugin.json           the plugin manifest
  marketplace.json      lets this same repo act as the marketplace
skills/
  hico-forge-vca/
    SKILL.md            the workflow and the judgement calls
    references/
      vca-master-prompt.md          the actual spec (v1.1)
      security-audit-for-vcas.md    how to read an audit for a Forge app
    assets/backend/     reference vault_client.py, vault_mock.py, ai_jobs.py
    assets/             manifest.example.json
    scripts/            compliance_check.sh — 12 checks, §11 plus security
  vibe-code-security-audit/
    SKILL.md            the audit procedure
    references/         the checklist and the report format
```

`references/vca-master-prompt.md` is kept byte-identical to the platform team's
`vault/docs/forge-vca-master-prompt.md`. **If the two ever disagree, the live doc
wins and this skill is what needs updating.**

---

## Changing it

The GitHub repo is the source of truth. Edit `skills/hico-forge-vca/SKILL.md`,
bump `version` in **both** `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` — they have to match or installs fail — and
push to the default branch. With `autoUpdate` on, everyone follows.

The version is what makes updates land. Leave it unchanged and Claude Code has no
reason to re-fetch.
