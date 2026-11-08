# agent-plugin — the canonical AccessMCP plugin package

An **Agent Plugins 1.0** package — `plugin.json` (with the standard
`$schema`), `mcp.json`, `skills/`, `bootstrap/` — consumable as-is by clients
that speak the standard (Cursor, VS Code), and the base every other client
adapter is derived from. **Do not edit per-client copies**; edit here (or
rather: upstream in the product repo's `packaging/`, which syncs to here),
and let CI verify the copies match.

## Plugin-root variable

`mcp.json` uses `${CLAUDE_PLUGIN_ROOT}`, **not** the Agent Plugins standard
`${PLUGIN_ROOT}`: Cursor's documentation says it expands `${CURSOR_PLUGIN_ROOT}`
and `${CLAUDE_PLUGIN_ROOT}` in an Agent Plugin's `mcp.json` and does not expand
`${PLUGIN_ROOT}`, so with the standard token the bootstrap path never resolved
and the server could not start. Claude Code expands `${CLAUDE_PLUGIN_ROOT}`
itself. The package still declares the Agent Plugins `$schema`; the schema puts
no constraint on variable text in `args`.

| Client | Variable | Where |
|---|---|---|
| Cursor | `${CLAUDE_PLUGIN_ROOT}` | this package, unchanged |
| Claude Code | `${CLAUDE_PLUGIN_ROOT}` | `../claude-plugin/.mcp.json`, same launch line plus the database `env` |
| VS Code | not verified for this package (its docs list `${PLUGIN_ROOT}` for Agent Plugins 1.0 and `${CLAUDE_PLUGIN_ROOT}` for the Claude format) | use the Access-MCP extension |
| Codex (D5 adapter) | per OpenAI plugin docs | derived at D5 |

The sync workflow checks that this package does not use `${PLUGIN_ROOT}` and
that the Claude Code adapter's launch line is identical to this one.

## Choosing the database

The server works on exactly one database and refuses to start without it, so a
plugin install has to say which. How depends on the client:

| Client | How the database is chosen |
|---|---|
| Claude Code | Asks for an "Access database" when you install or enable the plugin (`/plugin install accessmcp@accessmcp`); passed to the server as `AccessFilePath`. Change it with `/plugin configure accessmcp@accessmcp`. From a shell, `claude plugin install` does not prompt: pass `--config access_file_path=C:\Data\YourDatabase.accdb`. One database per plugin install. |
| Cursor | A plugin has no per-user setting. Set the **`AccessFilePath`** Windows environment variable to the `.accdb` path (user level is enough) and restart Cursor; it is global to every project. **Not verified end to end in Cursor**: whether the variable reaches the plugin's server is unconfirmed (Cursor's docs say stdio servers run in an isolated environment), so prefer the extension. For several databases, or per-project choice, use the **Access-MCP extension** (Connections view) or one `mcp.json` entry per database (`templates/cursor/` in the public repo). |

Without a database the bootstrap stops before downloading anything, prints one
line on stderr (`Access-MCP plugin: no database configured. ...`, naming the fix
for Claude Code and for Cursor) and exits 2.

## What the bootstrap does — and the four install families

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

1. **This plugin (Cursor and other Agent Plugin clients)** → the shared
   version cache above.
2. **The Claude Code plugin** → the signed exe bundled in the plugin
   (`claude-plugin/server/accessmcp.exe`), which updates with the plugin; it
   does not use the bootstrap (the Anthropic plugin directory refuses a
   download-and-run launcher).
3. **Manual / `install-accessmcp.ps1`** → a standalone exe wherever the user
   puts it; the bootstrap neither uses nor touches it.
4. **Claude Desktop `.mcpb`** → its own bundled exe.

Platform nuance: on macOS/Linux the plugin fails before the bootstrap can
even print its explanatory error — `powershell.exe` does not exist there, so
the client surfaces its own "command not found". That is accepted (plan §6):
manifests declare Windows-only wherever the format allows, and the docs say
it plainly; no cross-platform launcher will be built to prettify a platform
we do not support.

The direct-download contract is untouched by all of this: a bare
`accessmcp.exe` pointed at by a hand-written `mcp.json` keeps working with
none of these files present. Full contract:
`docs/plugin-platforms-development-plan.md` §2.2–§2.3 in the product repo.
