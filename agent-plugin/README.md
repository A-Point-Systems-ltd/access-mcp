# agent-plugin — the canonical AccessMCP plugin package

An **Agent Plugins 1.0** package — `plugin.json` (with the standard
`$schema`), `mcp.json`, `skills/`, `bootstrap/` — consumable as-is by clients
that speak the standard (Cursor, VS Code), and the base every other client
adapter is derived from. **Do not edit per-client copies**; edit here (or
rather: upstream in the product repo's `packaging/`, which syncs to here),
and let CI verify the copies match.

## Plugin-root variables

`mcp.json` uses the Agent Plugins standard `${PLUGIN_ROOT}` variable. Client
adapters that use a different variable are **derived** by the sync workflow,
never edited by hand:

| Client | Variable | Where |
|---|---|---|
| Cursor / VS Code (Agent Plugins 1.0) | `${PLUGIN_ROOT}` | this package, unchanged |
| Claude Code | `${CLAUDE_PLUGIN_ROOT}` | `../claude-plugin/.mcp.json`, derived |
| Codex (D5 adapter) | per OpenAI plugin docs | derived at D5 |

CI fails if the canonical package loses the standard token or an adapter
still carries it un-substituted.

## What the bootstrap does — and the three install families

`bootstrap/bootstrap.ps1` runs **exactly the version this plugin pins** in
`bootstrap/release-manifest.json`, from the shared version cache
(`%LOCALAPPDATA%\Programs\AccessMCP\versions\<v>\accessmcp.exe`),
downloading and SHA256-verifying it from the version-pinned GitHub Release
URL on first use. Two plugins pinned to the same version share one copy;
plugins pinned to different versions are isolated — one client updating
never changes what another runs. Updates arrive by updating the plugin
(which moves the pin); a throttled, best-effort remote check only prints a
notice when something newer exists.

Deliberately separate install families:

1. **Plugins** → the shared version cache above.
2. **Manual / `install-accessmcp.ps1`** → a standalone exe wherever the user
   puts it; the bootstrap neither uses nor touches it.
3. **Claude Desktop `.mcpb`** → its own bundled exe.

The direct-download contract is untouched by all of this: a bare
`accessmcp.exe` pointed at by a hand-written `mcp.json` keeps working with
none of these files present. Full contract:
`docs/plugin-platforms-development-plan.md` §2.2–§2.3 in the product repo.
