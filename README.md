<p align="center">
  <img src="https://access-mcp.ai/favicon.svg" alt="Access-MCP" width="600">
</p>

<h1 align="center">Access-MCP</h1>

<p align="center">
  <strong>The MCP server that lets AI agents work natively with Microsoft Access.</strong><br>
  27 tools &middot; Windows + Access &middot; Free tier + Pro
</p>

<p align="center">
  <a href="https://access-mcp.ai">Website</a> &middot;
  <a href="https://access-mcp.ai/docs">Docs</a> &middot;
  <a href="https://github.com/A-Point-Systems-ltd/access-mcp/releases">Download</a> &middot;
  <a href="https://access-mcp.ai/support">Support</a> &middot;
  <a href="https://access-mcp.ai/migrate">Migration Services</a>
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-v2.1.0-blue">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows-0078D4">
  <img alt=".NET" src="https://img.shields.io/badge/.NET-9.0-512BD4">
  <img alt="License" src="https://img.shields.io/badge/license-Proprietary-gray">
</p>

---

## What is Access-MCP?

Access-MCP is a production-grade [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that gives AI coding agents — **Claude, Cursor, GitHub Copilot**, and any MCP-capable client — full, safe access to Microsoft Access databases on Windows.

Your agent can read schema, run SQL, refactor VBA, design forms, and manage database objects directly against live `.accdb`, `.mdb`, and `.adp` files. No ODBC setup. No CSV exports. Just point your agent at the database.

## Quick Start

### 1. Download

Grab the latest `MS.Access.MCP.exe` from the [Releases](https://github.com/A-Point-Systems-ltd/access-mcp/releases) page.

### 2. Configure your MCP client

Add this to your MCP configuration:

**Cursor** (`.cursor/mcp.json`):
```json
{
  "mcpServers": {
    "access-mcp": {
      "command": "c:\\access-mcp\\MS.Access.MCP.exe",
      "args": ["C:\\Path\\To\\YourDatabase.accdb"]
    }
  }
}
```

**Claude Code** (`.claude/settings.json`):
```json
{
  "mcpServers": {
    "access-mcp": {
      "command": "c:\\access-mcp\\MS.Access.MCP.exe",
      "args": ["C:\\Path\\To\\YourDatabase.accdb"]
    }
  }
}
```

### 3. Start using it

Just ask your agent to work with the database:

> "Show me all the tables in this Access database"
> "Refactor the VBA in the OrderEntry form to remove duplicate validation"
> "Create a query that joins Customers and Orders"

## 27 MCP Tools

| Category | Tools | Description |
|----------|-------|-------------|
| **Session** | `Session_OpenDatabase`, `Session_CloseDatabase`, `Session_Status` | Open/close databases, check connection status |
| **Schema** | `Schema_Tables`, `Schema_Queries`, `Schema_Relationships` | Explore database structure and relationships |
| **SQL** | `SQL_Select`, `SQL_Execute`, `SQL_ParameterizedQuery` | Run read and write queries safely |
| **VBA** | `VBA_Read`, `VBA_Updates`, `VBA_ListModules` | Read and refactor VBA code modules |
| **Forms** | `Form_List`, `Form_Read`, `Form_Design` | Inspect and modify form layouts |
| **Objects** | `Object_List`, `Object_Export`, `Object_Import` | Manage all database objects |
| **Data** | `Data_Read`, `Data_Insert`, `Data_Update`, `Data_Delete` | Full CRUD on table data |
| **Batch** | `Batch_Execute`, `Batch_Export` | Batch operations for efficiency |

> See the full [tool reference](https://access-mcp.ai/docs) for parameters and examples.

## Requirements

- **Windows 10/11** or Windows Server 2016+
- **Microsoft Access** installed locally (any version: 2003 or later)
- **.NET 9 Runtime** (bundled in the release)

## Pricing

| | Free | Pro |
|---|---|---|
| **Price** | $0 | $49/dev/month |
| **Read operations** | ~50/day | Unlimited |
| **Write operations** | - | Unlimited |
| **VBA read/write** | Read only | Full |
| **Forms & design** | - | Full |
| **Batch operations** | - | Full |
| **API key** | Free, no card | License key |

[Get your free API key](https://access-mcp.ai/#install) | [Upgrade to Pro](https://access-mcp.ai/#pricing)

## Free Skills & Rules

This repo includes free skills and rules for AI coding agents to work more effectively with Microsoft Access:

### Skills

- [`skills/claude/`](skills/claude/) — Skills for Claude Code that enhance Access database workflows
- [`skills/cursor/`](skills/cursor/) — Skills for Cursor that enhance Access database workflows

### Rules

- [`rules/claude/`](rules/claude/) — CLAUDE.md rules for working with Access databases
- [`rules/cursor/`](rules/cursor/) — `.cursorrules` for Access-aware coding assistance

## Documentation

Full documentation is available at [access-mcp.ai/docs](https://access-mcp.ai/docs), covering:

- Setup guides for Claude, Cursor, and Copilot
- Tool reference with parameters and examples
- VBA refactoring workflows
- Migration planning
- Troubleshooting

## About A-Point Systems

[A-Point Systems Ltd](https://apoint.co.il) has been modernizing legacy Microsoft Access systems since 2011. We build tools and provide services to help organizations move forward with confidence.

### Services

- **Access to SQL Server migration** — Full modernization of legacy Access databases
- **Access application development** — Custom Access solutions and maintenance
- **AI integration consulting** — Help your team adopt AI-powered development workflows

[Book a call](https://cal.com/apoint) | [hello@apoint.co.il](mailto:hello@apoint.co.il)

## Links

- [Website](https://access-mcp.ai)
- [Documentation](https://access-mcp.ai/docs)
- [Support](https://access-mcp.ai/support)
- [Migration Services](https://access-mcp.ai/migrate)
- [MSSQL-MCP](https://github.com/A-Point-Systems-ltd/mssql-mcp) — Our MCP server for SQL Server
- [A-Point Systems](https://apoint.co.il)
- [LinkedIn](https://linkedin.com/company/a-point-systems)

## License

Access-MCP is proprietary software by A-Point Systems Ltd. Free tier available for personal and evaluation use. See [pricing](https://access-mcp.ai/#pricing) for details.
