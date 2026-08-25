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
         "args": ["C:\\Data\\YourDatabase.accdb"]
       }
     }
   }
   ```

3. **Quit Claude Desktop completely and reopen it.** The config is read once at
   startup; closing the window is not enough — quit from the tray.

Replace `YOU` with your Windows user name (or the whole path with wherever you
put the exe), and the `args` entry with the database this server works on —
it is required, and the server only ever touches the file pinned there.
Backslashes are doubled because this is JSON.

## Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure claude-desktop -DatabasePath "C:\Data\YourDatabase.accdb"
```

It reads the existing file, adds one key, keeps everything else, and writes a
timestamped `.bak` next to the original first. See [`../installer/`](../installer/).

## One-click bundle

The one-click route is the `accessmcp.mcpb` bundle from GitHub Releases:
double-click it and Claude Desktop installs the server as an extension,
asking for your database file at install time (the `user_config` file picker
in [`mcpb/manifest.json`](mcpb/manifest.json) — that answer becomes the
required `args` pin). The bundle carries its own copy of the exe; the manual
route above stays the zero-extra-copies option. There is no `claude://` MCP
install deeplink — the bundle is the one-click.

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
- The database path in `args` is **required** (v2.4.0): the server works only
  on the file pinned there — the safety guard against an agent opening the
  wrong (say, production) database. The full argument list is in
  [`../README.md`](../README.md).
- Windows only. Microsoft Access must be installed for the same Windows user.
