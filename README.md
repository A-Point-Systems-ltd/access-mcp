<p align="center">
  <img src="https://access-mcp.ai/og-card.png" alt="Access-MCP" width="600">
</p>

<h1 align="center">Access-MCP</h1>

<p align="center">
  <strong>The MCP server that lets AI agents work natively with Microsoft Access.</strong><br>
  97 tools packed into 27 smart tools &middot; VS Code &amp; Cursor extension &middot; Windows + Access &middot; Free tier + Pro
</p>

<p align="center">
  <a href="https://marketplace.visualstudio.com/items?itemName=apoint.ms-access-mcp"><img src="https://img.shields.io/visual-studio-marketplace/v/apoint.ms-access-mcp?label=VS%20Marketplace" alt="VS Marketplace version"></a>
  <a href="https://open-vsx.org/extension/apoint/ms-access-mcp"><img src="https://img.shields.io/open-vsx/v/apoint/ms-access-mcp?label=Open%20VSX" alt="Open VSX version"></a>
  <a href="https://marketplace.visualstudio.com/items?itemName=apoint.ms-access-mcp"><img src="https://img.shields.io/visual-studio-marketplace/i/apoint.ms-access-mcp" alt="VS Marketplace installs"></a>
  <img src="https://img.shields.io/badge/runtime-self--contained-blue" alt="Runtime: self-contained">
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

**97 tools packed into 27 smart tools.** Each smart tool groups related
operations, so your agent loads 27 tool definitions instead of 97 — less
context spent on tool lists, fewer wrong calls and retries, fewer tokens per
task.

This is the **distribution repository**: releases, plugin packages, install
templates. The product's source code is closed; what ships from here is
`accessmcp.exe` (as a signed release asset), plugin manifests, skills, and
an open-source bootstrap. Sign-in is built in: run `accessmcp login` once
per machine (free account, ~20 seconds in the browser).

## Choose your AI client

| Client | Install |
|---|---|
| **VS Code / Cursor extension** (recommended) | [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=apoint.ms-access-mcp) · [Open VSX](https://open-vsx.org/extension/apoint/ms-access-mcp) (Cursor, Windsurf, VSCodium) — see below |
| **Claude Code** | `/plugin marketplace add A-Point-Systems-ltd/access-mcp` then `/plugin install accessmcp@accessmcp` |
| **Claude Desktop** | Download `accessmcp.mcpb` from [Releases](https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest) — double-click to install |
| **Cursor** | *Add to Cursor* button on [access-mcp.ai](https://access-mcp.ai), or [`templates/cursor/`](templates/cursor/) |
| **VS Code + Copilot** | Plugin (MCP + skills) or MCP-only — see [`templates/vscode/`](templates/vscode/) |
| **Codex** | `codex mcp add` / `config.toml` — see [`templates/codex/`](templates/codex/) |
| **Any other MCP client** | Point a stdio MCP config at `accessmcp.exe` (below) |

### VS Code / Cursor extension (recommended)

The **access-mcp.ai** extension (`apoint.ms-access-mcp`) bundles the server —
no exe download, no `mcp.json` editing.

1. Install it from the
   [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=apoint.ms-access-mcp)
   or [Open VSX](https://open-vsx.org/extension/apoint/ms-access-mcp)
   (Cursor, Windsurf, VSCodium).
2. Command Palette → **Access-MCP: Select / Change Database** and pick your
   `.accdb`, `.mdb` or `.adp`. The server starts only once a database is
   selected.
3. Open Copilot Chat → **Agent** mode and confirm **Access-MCP** is in the MCP
   servers list. The **Access-MCP** view in the activity bar lets you browse
   the database's objects.

**Cursor:** Cursor ignores MCP servers contributed by extensions. Run
**Access-MCP: Register Server in mcp.json (Cursor)** once (the extension
offers it automatically on first run), then reload. It writes an `ms-access`
entry to `~/.cursor/mcp.json` or `<workspace>/.cursor/mcp.json`.

Step-by-step guides: [VS Code](https://access-mcp.ai/docs/vscode-setup) ·
[Cursor](https://access-mcp.ai/docs/cursor-setup).

### Direct download / advanced setup

The exe is the product; everything above is convenience. This path always
works with none of it:

1. Download [`accessmcp.exe`](https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest/download/accessmcp.exe)
   (verify with `SHA256SUMS.txt` / `release-manifest.json` from the same release).
   It is self-contained — no .NET install needed.
2. Put it anywhere you like, and sign in once: `accessmcp login`.
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

## 97 tools packed into 27 smart tools

Your agent loads 27 tool definitions instead of 97 — less context spent on
tool lists, fewer wrong calls and retries, fewer tokens per task.

| Group | Smart tools | What it covers / key actions |
|---|---|---|
| **Session** (3) | `Session_OpenDatabase`, `Session_CloseDatabase`, `Session_GetDatabaseInfo` | Open, close and describe the database |
| **Object** (14) | `Object_List`, `Object_Get`, `Object_Create`, `Object_Delete`, `Object_Update`, `Object_Design`, `Object_Run`, `Object_Close`, `Object_GetProperties`, `Object_SetProperties`, `Object_GetControlProperties`, `Object_SetControlProperties`, `Object_AddControls`, `Object_DeleteControls` | List 7 object types, read 6 aspects of an object, create / update / delete / design / run / close objects, and read or edit object and control properties and controls |
| **Query** (3) | `Query_Read`, `Query_Execute`, `Query_ExecuteBatch` | Read queries, single action statements, and batches |
| **Data** (1) | `Data_Transfer` | Import and export CSV or Excel |
| **VBA** (2) | `VBA_Read`, `VBA_Updates` | Read: `getCode`, `getProjects`, `getModules`, `getReferences`, `search`. Updates (12 actions): `setCode`, `setProcedure`, `patchProcedure`, `createModule`, `compile`, `addReferenceByGuid`, `addReferenceByFile`, `removeReference`, `addProcedure`, `deleteModule`, `deleteProcedure`, `setCodeFromFile` |
| **System** (4) | `System_Read`, `System_Updates`, `System_Logs`, `System_Audit` | Read: `getAutoCloseStatus`, `getReadOnly`, `getDatabaseInfo`, `healthCheck`, `showAccess`, `hideAccess`, `getDialogHistory`, `getToolContracts`. Updates: `setAutoClose`, `setReadOnly`. Logs: `get`, `clear`. Audit: `session`, `getTraces`, `readTrace` |

`tools/list` also shows the account tools `access_login` and `access_whoami`.
The 97 legacy granular tool names keep working — an alias map routes them to
the smart tools.

## Requirements

- Windows 10/11 x64 (or Windows Server, 64-bit) — **native**, not WSL or a
  remote container ([supported platforms](https://access-mcp.ai/docs/supported-platforms))
- Microsoft Access 2010 or later, 32-bit or 64-bit (the server drives it via COM)
- Extension: VS Code 1.101+, or an Open VSX editor (Cursor, Windsurf, VSCodium)
- Exe: self-contained — no .NET runtime to install
- Works with `.accdb`, `.mdb` and (with limits) `.adp`

## Pricing

- **Free** — read-only access, 50 operations/day. Free account: sign in with
  Microsoft, Google or GitHub. No card.
- **14-day trial** — all 27 smart tools. Starts at your first sign-in. No card.
- **Pro** — $49/developer/month or $529/year: unlimited operations, writes,
  VBA, forms and batch.
- **Enterprise** — custom.

Details: <https://access-mcp.ai>.

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
<a href="https://github.com/A-Point-Systems-ltd/ms-sql-mcp">MSSQL-MCP</a>
(<a href="https://marketplace.visualstudio.com/items?itemName=apoint.ms-sql-mcp">VS Marketplace</a> &middot;
<a href="https://open-vsx.org/extension/apoint/ms-sql-mcp">Open VSX</a>):
a free, MIT-licensed SQL Server MCP server with 23 tools, strict read/write
routing, named connections (including read-only), compact TOON query results
and an AI Insights cache so repeat investigations cost fewer tokens.</sub>
