# agent-plugin — the canonical AccessMCP plugin package

One package — `plugin.json`, `mcp.json`, `skills/`, `bootstrap/` — from which
every per-client plugin is derived. **Do not edit per-client copies**; edit
here (or rather: upstream in the product repo's `packaging/`, which syncs to
here), and let CI verify the copies match.

## The `__PLUGIN_ROOT__` token

`mcp.json` here is a *template*: the `__PLUGIN_ROOT__` token is replaced by
each client adapter with that client's plugin-root variable:

| Client | Replacement |
|---|---|
| Claude Code (`../claude-plugin/`) | `${CLAUDE_PLUGIN_ROOT}` |
| Cursor / VS Code (Agent Plugins) | per their docs — verify at D3 kickoff |
| Codex (D5 adapter) | per OpenAI plugin docs — verify at D5 kickoff |

CI fails if a derived copy still contains the raw token.

## What the bootstrap does

`bootstrap/bootstrap.ps1` launches `accessmcp.exe` from the canonical
versioned install under `%LOCALAPPDATA%\Programs\AccessMCP\`
(`current.json` + `versions\<v>\accessmcp.exe`), downloading and
SHA256-verifying it from a GitHub Release on first use. Full contract:
`docs/plugin-platforms-development-plan.md` §2.2–§2.3 in the product repo.
The direct-download path never depends on it: a bare `accessmcp.exe` pointed
at by a hand-written `mcp.json` keeps working with none of this present.
