# Cursor

Format, file locations and the install-link scheme verified against
<https://cursor.com/docs/mcp> and <https://cursor.com/docs/mcp/install-links>
(August 2026).

---

## Manual

Two files, same shape — pick the scope you want:

| File | Scope |
|---|---|
| `%USERPROFILE%\.cursor\mcp.json` (`~/.cursor/mcp.json`) | global — every project |
| `.cursor\mcp.json` in the project | that project only |

Merge the entry from [`mcp.template.json`](mcp.template.json) into the existing
`mcpServers` object — do not replace a file that already has servers in it:

```json
{
  "mcpServers": {
    "accessmcp": {
      "type": "stdio",
      "command": "C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe",
      "args": ["C:\\Data\\YourDatabase.accdb"]
    }
  }
}
```

Replace `YOU` with your Windows user name (or the whole path with wherever you
put the exe), and the `args` entry with the database this server works on —
it is required, and the server only ever touches the file pinned there.
Restart Cursor afterwards.

## One-click install link

Cursor's deeplink scheme is:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=$NAME&config=$BASE64_ENCODED_CONFIG
```

where `$BASE64_ENCODED_CONFIG` is base64 of the **single server object** — the
inner value only, without the server name wrapping it. Because the exe path
contains your Windows user name and the config pins your database, a link is
per-machine. Generate yours:

```powershell
$exe    = "$env:LOCALAPPDATA\Programs\AccessMCP\accessmcp.exe"
$db     = 'C:\Data\YourDatabase.accdb'   # the database this server works on — required
$config = [ordered]@{ type = 'stdio'; command = $exe; args = @($db) } | ConvertTo-Json -Compress
$b64    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($config))
$link   = "cursor://anysphere.cursor-deeplink/mcp/install?name=accessmcp&config=$b64"
$link                 # paste it in a browser, or:
Start-Process $link    # hand it straight to Cursor
```

For the placeholder path above, that yields:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=accessmcp&config=eyJ0eXBlIjoic3RkaW8iLCJjb21tYW5kIjoiQzpcXFVzZXJzXFxZT1VcXEFwcERhdGFcXExvY2FsXFxQcm9ncmFtc1xcQWNjZXNzTUNQXFxhY2Nlc3NtY3AuZXhlIiwiYXJncyI6WyJDOlxcRGF0YVxcWW91ckRhdGFiYXNlLmFjY2RiIl19
```

(decodes to `{"type":"stdio","command":"C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe","args":["C:\\Data\\YourDatabase.accdb"]}` —
it will not work until `YOU` is your real user name and the database path is
your real file, which is exactly why the snippet above exists.)

## Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure cursor -DatabasePath "C:\Data\YourDatabase.accdb"
```

It merges into the **global** `%USERPROFILE%\.cursor\mcp.json`, backs the file up
first, and prints your generated deeplink so you can use that instead if you
prefer. See [`../installer/`](../installer/).

---

## Gotchas from Cursor's own docs

- **Cursor runs stdio servers in an isolated environment.** Use an absolute path
  to the exe and assume nothing about `PATH` or shell profile — even after the
  installer adds `%LOCALAPPDATA%\Programs\AccessMCP` to your user `PATH`.
- **Team allowlists approve servers by command pattern**, so keep the install
  path stable. `%LOCALAPPDATA%\Programs\AccessMCP\accessmcp.exe` is the path the
  installer uses on every machine, which makes one allowlist entry enough.
- The Cursor CLI can also add a server (`agent mcp add ...`), and the Settings →
  MCP UI can add one interactively. Both end up in the same `mcp.json`.

## Verify

```powershell
"C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe" doctor
```

Then, in Cursor chat: "Open my database and show me the tables" — the agent
works on the database pinned in `args`.

## Notes

- The database path in `args` is **required** (v2.4.0): the server works only
  on the file pinned there — the safety guard against an agent opening the
  wrong (say, production) database. The full argument list is in
  [`../README.md`](../README.md).
- Skills/rules: the `access-*` skill bodies in
  [`../claude-plugin/skills/`](../claude-plugin/skills/) are Claude Code plugin
  skills. Whether Cursor loads that format unmodified is **not verified here** —
  treat porting them to Cursor rules as an open item, not a shipped feature.
- Windows only. Microsoft Access must be installed for the same Windows user.
