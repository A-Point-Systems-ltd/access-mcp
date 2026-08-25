# OpenAI Codex CLI

Codex configures MCP servers in **TOML**, not JSON — it is the one client here
that does.

Verified against the `openai/codex` source rather than a blog post
(August 2026):

| Fact | Where it is defined |
|---|---|
| config file is `config.toml` inside the Codex home | `codex-rs/config/src/lib.rs` → `CONFIG_TOML_FILE = "config.toml"` |
| Codex home is `~/.codex`, overridable by `CODEX_HOME` | `codex-rs/core/src/config/mod.rs` (`codex_home`, `find_codex_home`) |
| the table is `mcp_servers` | `codex-rs/config/src/mcp_edit.rs` → `parsed.get("mcp_servers")` |
| a stdio server is `command` + `args` + `env` | `codex-rs/config/src/mcp_types.rs` → `McpServerTransportConfig::Stdio` |
| `codex mcp add <name> -- <command> [args...]` | `codex-rs/cli/src/mcp_cmd.rs` (`codex mcp add [OPTIONS] <NAME> (--url <URL> \| -- <COMMAND>...)`) |

On Windows that path is `%USERPROFILE%\.codex\config.toml`. The file is **not**
created by the installer of Codex itself — if it does not exist yet, create it.

---

## Manual — the CLI (recommended, no TOML editing)

```powershell
codex mcp add accessmcp -- "C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe" "C:\Data\YourDatabase.accdb"
```

Everything after `--` is the command line Codex will run — the required
database path first, then any extra flags:

```powershell
codex mcp add accessmcp -- "C:\...\accessmcp.exe" "C:\Data\YourDatabase.accdb" --read-only
```

Then `codex mcp list` to confirm, and `/mcp` inside a Codex session to see the
tools. `codex mcp remove accessmcp` undoes it.

## Manual — editing the file

Append the table from [`config.template.toml`](config.template.toml) to
`%USERPROFILE%\.codex\config.toml`:

```toml
[mcp_servers.accessmcp]
command = 'C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe'
args = ['C:\Data\YourDatabase.accdb']
```

Replace `YOU` with your Windows user name (or the whole path with wherever you
put the exe), and the `args` entry with the database this server works on —
it is required, and the server only ever touches the file pinned there.
Single quotes make these TOML literal strings, so backslashes stay as they
are — that is why this template does not double them the way the JSON ones do.

## Installer

```powershell
.\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure codex
```

PowerShell has no TOML parser, and pulling one in for a single table would be a
worse trade than doing the edit precisely. The installer therefore does a
**targeted** edit: back up the file, find an existing `[mcp_servers.accessmcp]`
header, replace exactly that block up to the next table header, or append the
block if there is none. Every other byte of your `config.toml` is left alone.

It refuses to touch the file — and prints the snippet for you to paste — when it
finds `mcp_servers` written as a top-level inline table (`mcp_servers = { ... }`)
rather than as `[mcp_servers.<name>]` sections, because rewriting that form
safely is beyond a targeted edit. See [`../installer/`](../installer/).

## One-click link

None. Codex has no documented deeplink scheme; `codex mcp add` is the one-liner.

---

## Verify

```powershell
"C:\Users\YOU\AppData\Local\Programs\AccessMCP\accessmcp.exe" doctor
codex mcp list
```

## Notes

- The database path in `args` is **required** (v2.4.0): the server works only
  on the file pinned there — the safety guard against an agent opening the
  wrong (say, production) database. The full argument list is in
  [`../README.md`](../README.md).
- No `type` field: Codex infers the transport from `command` (stdio) vs `url`
  (streamable HTTP).
- A project-scoped `.codex/config.toml` also exists for trusted projects; this
  packaging targets the per-user file, which matches how the other three clients
  are configured here.
- Windows only. Microsoft Access must be installed for the same Windows user.
