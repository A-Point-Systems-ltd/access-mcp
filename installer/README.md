# `install-accessmcp.ps1` — per-user installer, no admin rights

Windows only. Windows PowerShell 5.1 (what ships with Windows) and PowerShell 7
on Windows.

```powershell
# copy the exe, add it to PATH, configure everything, run the doctor
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure all

# see exactly what it would do, and touch nothing
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure all -DryRun

# one client only
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure cursor,codex

# undo everything it did
.\install-accessmcp.ps1 -Uninstall
```

If PowerShell refuses to run the script, it is the execution policy, not the
script: `powershell -ExecutionPolicy Bypass -File .\install-accessmcp.ps1 ...`
(per-process, no admin, nothing permanently changed).

---

## What it does, in order

1. **Refuses to run on anything but Windows**, with a reason rather than a stack
   trace.
2. **Puts the exe at `%LOCALAPPDATA%\Programs\AccessMCP\accessmcp.exe`.**
   Never Program Files — writing there is the single thing that would force a
   UAC prompt. Same build already installed? It says so and skips the copy.
3. **Adds that directory to the *user* `PATH`** (`HKCU\Environment`), then
   broadcasts `WM_SETTINGCHANGE` so open shells notice. The machine `PATH` is
   never touched. Written through the registry rather than
   `[Environment]::SetEnvironmentVariable` so a `REG_EXPAND_SZ` `PATH` stays
   `REG_EXPAND_SZ` — the .NET call can flatten it and break every `%VAR%`
   already in it.
4. **Merges the `accessmcp` entry into the client configs you named.**
5. **Runs `accessmcp doctor`** by absolute path and prints the verdict.

Every step that writes, overwrites or deletes prints what it is about to do
first. `-DryRun` prints the same lines and performs none of them.

## Merge, never overwrite

| Client | File | How |
|---|---|---|
| Claude Code | `~/.claude.json` (user scope) | **via the `claude` CLI** — `claude mcp add --transport stdio --scope user accessmcp -- <exe>`. That file holds far more than MCP servers; the CLI owns it, so this script never hand-edits it. No CLI on `PATH` → it prints the exact command and changes nothing. |
| Claude Desktop | `%APPDATA%\Claude\claude_desktop_config.json` | read JSON → add one key under `mcpServers` → write back. Also merges into a `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\` copy **if one already exists** (the MSIX split — see [`../claude-desktop/README.md`](../claude-desktop/README.md)). |
| Cursor | `%USERPROFILE%\.cursor\mcp.json` | same JSON merge; then prints a ready-made `cursor://` install link for this machine. |
| Codex | `%CODEX_HOME%` or `%USERPROFILE%\.codex\config.toml` | targeted TOML edit — replace the `[mcp_servers.accessmcp]` block up to the next table header, or append it. No TOML parser is pulled in, and no other byte of the file is rewritten. |

Before any JSON or TOML file is modified it is copied to
`<file>.<timestamp>.accessmcp.bak` beside itself. A user with five other MCP
servers keeps all five — the script prints how many it is preserving. Files are
written **UTF-8 without a BOM**: `Set-Content -Encoding UTF8` on PowerShell 5.1
emits a BOM, and a BOM ahead of `{` breaks `JSON.parse` in Electron-based
clients. After each JSON write the file is read back and the entry checked, so a
silent serialisation failure cannot pass as success.

An unparseable config is never overwritten — the script says which file and
stops.

## What `-Uninstall` reverses

- the `accessmcp` entry in each client config (Claude Code via
  `claude mcp remove`, the JSON clients by key removal, Codex by removing the
  `[mcp_servers.accessmcp]` block **and its sub-tables**, which would otherwise
  re-declare a server with no command);
- the install directory's entry in the user `PATH`;
- `%LOCALAPPDATA%\Programs\AccessMCP\accessmcp.exe`, and the directory itself if
  nothing else is left in it.

Every file it touches is backed up first, exactly as on install.

**Guard rail:** a client entry whose `command` does not point inside the install
directory is *left alone*, with a warning — it is a config someone else wrote,
and an uninstaller has no business deleting it. `-Force` overrides.

**Deliberately not removed:**

- your sign-in (`%APPDATA%\AccessMCP\credentials.bin`) — uninstalling is not
  signing out;
- any `*.accessmcp.bak` backup, ever;
- any `accessmcp.exe` you installed by hand somewhere else, and any config
  pointing at it. That is the whole point: the direct-download path is
  independent of this script in both directions.

## Parameters

| Parameter | Meaning |
|---|---|
| `-ExePath <path>` | the exe to install |
| `-FromRelease -ReleaseUrl <https url>` | download it instead. **No URL is hardcoded** — a stale URL baked into an installer is worse than no URL, and this script must never fetch something you did not name. Releases: <https://github.com/A-Point-Systems-ltd/MS.Access.MCP/releases> |
| `-InstallDir <path>` | default `%LOCALAPPDATA%\Programs\AccessMCP`. Anywhere protected will want admin, which the default exists to avoid. |
| `-Configure claude-code,claude-desktop,cursor,codex,all,none` | default `none` on install, `all` on `-Uninstall` |
| `-ServerName <name>` | the key written into the configs; default `accessmcp` |
| `-DatabasePath <path>` | pin the server to one database (first argument). Default: plug & play — you tell the agent which database to open. |
| `-ReadOnly` | add `--read-only` to every config it writes |
| `-DryRun` | print everything, change nothing |
| `-SkipDoctor` | skip the verification step |
| `-Force` | on `-Uninstall`, remove entries this installer did not write |
| `-Uninstall` | reverse it all |

## What it never does

No secrets. No telemetry. Nothing that phones home — the only network call it
can make is the `-FromRelease -ReleaseUrl` download you asked for. It never
elevates, never writes outside your user profile, and never strips the
mark-of-the-web from the exe (it tells you the `Unblock-File` command instead;
removing a security marker is your call).

## The line it does not cross

Nothing here is required for `accessmcp.exe` to run. Delete the `PATH` entry,
delete the configs, delete this script — an exe you downloaded and pointed an
`mcp.json` at keeps working. See [`../README.md`](../README.md) and
[`DOCTOR-SPEC.md`](DOCTOR-SPEC.md).
