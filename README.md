<p align="center">
  <img src="https://access-mcp.ai/favicon.svg" alt="Access-MCP" width="64">
</p>

<h1 align="center">Access-MCP</h1>

<p align="center">
  <strong>The MCP server that lets AI agents work natively with Microsoft Access.</strong><br>
  27 tools &middot; Windows + Access &middot; free tier + 14-day full trial + Pro
</p>

<p align="center">
  <a href="https://access-mcp.ai">Website</a> &middot;
  <a href="https://access-mcp.ai/docs">Docs</a> &middot;
  <a href="https://github.com/A-Point-Systems-ltd/access-mcp/releases">Download</a> &middot;
  <a href="https://access-mcp.ai/support">Support</a> &middot;
  <a href="https://access-mcp.ai/migrate">Migration Services</a>
</p>

---

Access-MCP gives AI agents — **Claude, Cursor, GitHub Copilot, Codex**, and
any MCP-capable client — full, structured access to Microsoft Access
databases on Windows: read schema, run SQL, refactor VBA, design forms and
reports, directly against live `.accdb`/`.mdb` files.

This is the **distribution repository**: releases, plugin packages, install
templates. The product's source code is closed; what ships from here is
`accessmcp.exe` (as a signed release asset), plugin manifests, skills, and
an open-source bootstrap. Sign-in is built in: run `accessmcp login` once
per machine (free account, ~20 seconds in the browser).

## Choose your AI client

| Client | Install |
|---|---|
| **Claude Code** | `/plugin marketplace add A-Point-Systems-ltd/access-mcp` then `/plugin install accessmcp@accessmcp` |
| **Claude Desktop** | Download `accessmcp.mcpb` from [Releases](https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest) — double-click to install |
| **Cursor** | *Add to Cursor* button on [access-mcp.ai](https://access-mcp.ai), or [`templates/cursor/`](templates/cursor/) |
| **VS Code + Copilot** | Plugin (MCP + skills) or MCP-only — see [`templates/vscode/`](templates/vscode/) |
| **Codex** | `codex mcp add` / `config.toml` — see [`templates/codex/`](templates/codex/) |
| **Any other MCP client** | Point a stdio MCP config at `accessmcp.exe` (below) |

### Direct download / advanced setup

The exe is the product; everything above is convenience. This path always
works with none of it:

1. Download [`accessmcp.exe`](https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest/download/accessmcp.exe)
   (verify with `SHA256SUMS.txt` / `release-manifest.json` from the same release).
2. Put it anywhere you like.
3. Point your client's MCP config at it, with the database this server works
   on pinned in `args` — required; the server only ever touches the file
   pinned there:

```json
{
  "mcpServers": {
    "accessmcp": {
      "command": "C:\\path\\to\\accessmcp.exe",
      "args": ["C:\\Data\\YourDatabase.accdb"]
    }
  }
}
```

Or let [`installer/install-accessmcp.ps1`](installer/) do it: per-user, no
admin rights, merges (never overwrites) your existing client configs.

## Requirements

- Windows 10/11 or Windows Server, 64-bit — **native**, not WSL or a remote
  container ([supported platforms](https://access-mcp.ai/docs/supported-platforms))
- Microsoft Access installed (the server drives it via COM)
- Works with `.accdb`, `.mdb` and (with limits) `.adp`

## What's in this repository

| Path | What |
|---|---|
| [`agent-plugin/`](agent-plugin/) | The canonical plugin package: manifest, skills, open-source bootstrap |
| [`claude-plugin/`](claude-plugin/) | Claude Code adapter over the canonical package |
| [`.claude-plugin/`](.claude-plugin/) | Marketplace manifest for `/plugin marketplace add` |
| [`templates/`](templates/) | Per-client MCP config templates (Claude Desktop/Code, Cursor, VS Code, Codex) |
| [`installer/`](installer/) | `install-accessmcp.ps1` + diagnostics spec |
| [`compliance/`](compliance/) | Directory-submission preflight checklist |

Release assets (`accessmcp.exe`, `accessmcp.mcpb`, `SHA256SUMS.txt`,
`release-manifest.json`) are published here by the product's release
pipeline; no binaries live in git.

## Privacy

Your database contents and object names never leave your machine — the
server-side account only sees identity, version, machine fingerprint and
per-tool usage counts. Full policy: <https://access-mcp.ai/privacy>.

## License

Proprietary — see [`LICENSE`](LICENSE). The bootstrap script and the plugin
manifests in this repository are provided openly so you can audit exactly
what runs on your machine; the product binary is closed-source.

---

<sub>From A-Point Systems, makers of the open-source
<a href="https://github.com/A-Point-Systems-ltd/ms-sql-mcp">MSSQL-MCP</a>.</sub>
