# Claude Code

Three routes, all pointing at the same `accessmcp.exe`. Pick one.

Format verified against <https://code.claude.com/docs/en/mcp> (August 2026).

---

## 1. Manual — `.mcp.json` in your project

Copy [`mcp.template.json`](mcp.template.json) to `.mcp.json` in the root of the
project you work in, and fix the path:

```json
{
  "mcpServers": {
    "accessmcp": {
      "type": "stdio",
      "command": "C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe",
      "args": []
    }
  }
}
```

Replace `YOU` with your Windows user name, or the whole path with wherever you
put the exe. Backslashes are doubled because this is JSON.

Claude Code asks for approval the first time it sees a project-scoped server —
that prompt is expected. `claude mcp reset-project-choices` resets the answer.

## 2. Manual — the CLI, no file editing

```powershell
claude mcp add --transport stdio --scope user accessmcp -- "C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe"
```

Scopes (from the docs above):

| Scope | Where it is stored | Visible in |
|---|---|---|
| `local` (default) | `~/.claude.json`, under the current project's path | this project, only you |
| `project` | `.mcp.json` in the project root | this project, everyone (check it in) |
| `user` | `~/.claude.json` | all your projects, only you |

`--` separates Claude's own flags from the command it runs. Everything after it
is passed to `accessmcp.exe` untouched, so extra arguments go there:

```powershell
claude mcp add --transport stdio --scope user accessmcp -- "C:\...\accessmcp.exe" --read-only
```

Check it: `claude mcp list` → `accessmcp ✔ Connected`. Remove it:
`claude mcp remove accessmcp`.

## 3. Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure claude-code
```

The installer prefers the `claude` CLI for this client (route 2 above) precisely
so it never hand-edits `~/.claude.json` — that file holds far more than MCP
servers, and a merge bug there would cost a user their whole Claude Code state.
If `claude` is not on `PATH`, the installer prints the exact command instead of
guessing. See [`../installer/`](../installer/).

---

## As a plugin (skills included)

The plugin bundle lives in [`../../claude-plugin/`](../../claude-plugin/): the
same MCP server plus the `access-*` skills, installed as one unit. It is listed
in [`../../.claude-plugin/marketplace.json`](../../.claude-plugin/marketplace.json)
at this repository's root, so from anywhere:

```
/plugin marketplace add A-Point-Systems-ltd/access-mcp
/plugin install accessmcp@accessmcp
```

The plugin's `.mcp.json` launches the open-source bootstrap
(`bootstrap/bootstrap.ps1`), which installs and runs `accessmcp.exe` from the
same canonical per-user path this directory documents
(`%LOCALAPPDATA%\Programs\AccessMCP`, versioned). Plugin and manual installs
therefore share one exe — no version drift between them.

---

## Verify

```powershell
"C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe" doctor
```

Then, in a Claude Code session, ask the agent to run `access_login` and open a
database.

## Notes

- `args` is `[]` on purpose — plug & play. Tell the agent which database to open
  ("Open the Access database at C:\Data\MyApp.accdb") instead of pinning one in
  the config. The full argument list is in [`../README.md`](../README.md).
- Windows only. Microsoft Access must be installed for the same Windows user.
