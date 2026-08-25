# AccessMCP — VS Code / GitHub Copilot

Two **different** install routes. Pick one; they do different things.

## Route 1 — AccessMCP Plugin (MCP server + skills)

The full Agent Plugin: the MCP server plus the AccessMCP skills
(inspect-db, health-report, modernization-plan). Installed through VS Code's
plugin mechanism (Plugin Marketplace / "Install Plugin From Source") from
this repository's `agent-plugin/` package.

> Plugin support in VS Code is gated by the `chat.plugins.enabled` setting,
> which ships **disabled** by default and may be managed by your
> organization. If you cannot enable it, use Route 2 — you lose the bundled
> skills, not the tools.

## Route 2 — MCP server only

Installs just the AccessMCP server, no skills. Either:

- **Install link** (from <https://access-mcp.ai>): a `vscode:mcp/install?...`
  URL that registers the server for you, or
- **Manual**: copy [`mcp.template.json`](mcp.template.json) to
  `.vscode/mcp.json` in your workspace (or add the server via the MCP
  settings UI), and fix the path:

```jsonc
{
  "servers": {
    "accessmcp": {
      "type": "stdio",
      "command": "C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe",
      "args": ["C:\\Data\\YourDatabase.accdb"]
    }
  }
}
```

Replace `YOU` with your Windows user name — or the whole path with wherever
you put `accessmcp.exe`. Always an absolute path. The `args` entry is the
database this server works on — **required** (v2.3.8); the server only ever
touches the file pinned there.

## Requirements

Native Windows with Microsoft Access installed. WSL and Remote development
targets are not supported — the server must run where Access runs. See
<https://access-mcp.ai/docs/supported-platforms>.

First run: `access_login` signs you in (free account, browser, ~20 seconds).

*Written against the VS Code Agent Plugins / MCP docs as of August 2026 —
re-verify the plugin-install mechanics at D3 kickoff (plan §D3).*
