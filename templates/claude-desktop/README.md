# Claude Desktop

Format and location verified against
<https://modelcontextprotocol.io/docs/develop/connect-local-servers> and
<https://modelcontextprotocol.io/docs/develop/build-server> (August 2026).

---

## Manual

1. **Settings → Developer → Edit Config** (or open the file directly):

   ```
   %APPDATA%\Claude\claude_desktop_config.json
   ```

   PowerShell: `notepad $env:APPDATA\Claude\claude_desktop_config.json`

2. Merge the `accessmcp` entry from
   [`claude_desktop_config.template.json`](claude_desktop_config.template.json)
   into the existing `mcpServers` object — **do not replace the file** if you
   already have servers there:

   ```json
   {
     "mcpServers": {
       "accessmcp": {
         "command": "C:\\Users\\YOU\\AppData\\Local\\Programs\\AccessMCP\\accessmcp.exe",
         "args": []
       }
     }
   }
   ```

3. **Quit Claude Desktop completely and reopen it.** The config is read once at
   startup; closing the window is not enough — quit from the tray.

Replace `YOU` with your Windows user name, or the whole path with wherever you
put the exe. Backslashes are doubled because this is JSON.

## Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure claude-desktop
```

It reads the existing file, adds one key, keeps everything else, and writes a
timestamped `.bak` next to the original first. See [`../installer/`](../installer/).

## One-click link

None. Claude Desktop has no documented `claude://` MCP install deeplink, so this
directory does not ship one. (Desktop extension bundles are a separate packaging
format and are **not** used here — they would put a second copy of the exe on
the machine, which the direct-download contract exists to avoid.)

---

## The Windows gotcha worth knowing about

If Claude Desktop was installed from the Microsoft Store (an MSIX package), the
app may read a **different, virtualised** copy of the config:

```
%LOCALAPPDATA%\Packages\Claude_<publisher-id>\LocalCache\Roaming\Claude\claude_desktop_config.json
```

while the **Edit Config** button opens the plain `%APPDATA%\Claude\...` path.
The two files are never synchronised, so an MCP server added to the wrong one is
silently ignored — no error, no log entry. Reported as
<https://github.com/anthropics/claude-code/issues/26073>.

**Uncertainty, stated plainly:** this is a bug report, not vendor documentation,
and the publisher-id segment may differ between builds. The installer therefore
writes `%APPDATA%\Claude\claude_desktop_config.json` **and**, if any
`%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\` directory already
exists, merges into that copy too — matching by wildcard rather than by a
hardcoded package name. It never creates the packaged directory. If your
`accessmcp` entry does not show up, check both paths.

## Verify

```powershell
"C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe" doctor
```

Then, in Claude Desktop, ask for `access_login` and open a database.

## Notes

- No `"type"` field here: the documented Claude Desktop shape is
  `command`/`args`/`env`. Cursor and Claude Code get `"type": "stdio"` because
  their docs show it; this packaging does not add fields a client's own
  documentation does not show.
- `args` is `[]` on purpose — plug & play. The full argument list is in
  [`../README.md`](../README.md).
- Windows only. Microsoft Access must be installed for the same Windows user.
