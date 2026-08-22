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
      "args": []
    }
  }
}
```

Replace `YOU` with your Windows user name, or the whole path with wherever you
put the exe. Restart Cursor afterwards.

## One-click install link

Cursor's deeplink scheme is:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=$NAME&config=$BASE64_ENCODED_CONFIG
```

where `$BASE64_ENCODED_CONFIG` is base64 of the **single server object** — the
inner value only, without the server name wrapping it. Because the exe path
contains your Windows user name, a link is per-machine. Generate yours:

```powershell
$exe    = "$env:LOCALAPPDATA\Programs\AccessMCP\accessmcp.exe"
$config = @{ type = 'stdio'; command = $exe; args = @() } | ConvertTo-Json -Compress
$b64    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($config))
$link   = "cursor://anysphere.cursor-deeplink/mcp/install?name=accessmcp&config=$b64"
$link                 # paste it in a browser, or:
Start-Process $link    # hand it straight to Cursor
```

For the placeholder path above, that yields:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=accessmcp&config=eyJ0eXBlIjoic3RkaW8iLCJjb21tYW5kIjoiQzpcXFVzZXJzXFxZT1VcXEFwcERhdGFcXExvY2FsXFxQcm9ncmFtc1xcQWNjZXNzTUNQXFxhY2Nlc3NtY3AuZXhlIiwiYXJncyI6W119
```

(decodes to `{"type":"stdio","command":"C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe","args":[]}` —
it will not work until `YOU` is your real user name, which is exactly why the
snippet above exists.)

## Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure cursor
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

Then, in Cursor chat: "Open the Access database at C:\Data\MyApp.accdb".

## Notes

- `args` is `[]` on purpose — plug & play. The full argument list is in
  [`../README.md`](../README.md).
- Skills/rules: the `access-*` skill bodies in
  [`../claude-plugin/skills/`](../claude-plugin/skills/) are Claude Code plugin
  skills. Whether Cursor loads that format unmodified is **not verified here** —
  treat porting them to Cursor rules as an open item, not a shipped feature.
- Windows only. Microsoft Access must be installed for the same Windows user.
