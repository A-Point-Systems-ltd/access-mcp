# Access-MCP Setup Guide

## Prerequisites

- Windows 10/11 or Windows Server 2016+
- Microsoft Access installed locally (2010, 2013, 2016, 2019, 2021, or 365)
- An MCP-capable AI client (Claude Desktop, Cursor, Claude Code, GitHub Copilot, etc.)

## Installation

1. Download `MS.Access.MCP.exe` from the [Releases](https://github.com/A-Point-Systems-ltd/access-mcp/releases) page
2. Extract to a folder (e.g., `C:\access-mcp\`)
3. Add the MCP server to your client configuration (see below)
4. Restart your MCP client

## Client Configuration

### Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

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

### Cursor

Create or edit `.cursor/mcp.json` in your project root:

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

### Claude Code

Edit `.claude/settings.json`:

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

### GitHub Copilot (VS Code)

Add to your VS Code settings:

```json
{
  "github.copilot.chat.mcpServers": {
    "access-mcp": {
      "command": "c:\\access-mcp\\MS.Access.MCP.exe",
      "args": ["C:\\Path\\To\\YourDatabase.accdb"]
    }
  }
}
```

## Getting Your API Key

### Free Tier
Visit [access-mcp.ai](https://access-mcp.ai/#install) to get a free API key. No credit card required. Includes read-only access with ~50 operations/day.

### Pro License
For unlimited operations, writes, VBA editing, forms, and batch operations: [access-mcp.ai/#pricing](https://access-mcp.ai/#pricing) — $49/developer/month.

## Troubleshooting

### "Access is not installed"
The MCP server requires a local installation of Microsoft Access. The Access Database Engine alone is not sufficient — a full Access installation is needed.

### "Database is locked"
Another process has the database open. Close Access or any other application using the file, then try again.

### "Permission denied"
Run your MCP client with appropriate permissions to access the database file path.

## Support

- [Documentation](https://access-mcp.ai/docs)
- [Support form](https://access-mcp.ai/support)
- [Email](mailto:hello@apoint.co.il)
- [Book a call](https://cal.com/apoint)
