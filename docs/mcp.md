# 🔌 MCP Server Management

Magic CLI supports MCP (Model Context Protocol) server integration, extending the AI assistant's tool and data access capabilities.

## What is MCP

MCP is an open standard protocol introduced by Anthropic in November 2024, providing a unified way for AI systems to connect to external tools and data sources. Like USB-C provides standardized connections for devices, MCP provides standardized data and tool integration for AI applications.

## Available Commands

### Show Loaded Tools
```bash
/mcp                # Display currently loaded MCP servers and tools
```

### Add Stdio Server
```bash
/mcp add <name> <command> [args...] [--env KEY=VALUE ...]
```

### Add SSE Server  
```bash
/mcp add-sse <name> <url>
```

### Remove Server
```bash
/mcp remove <name>
```

## Usage Examples

### Filesystem Access
```bash
/mcp add filesystem npx -y @modelcontextprotocol/server-filesystem ~/Documents
```

### GitHub Integration
```bash
/mcp add github npx -y @modelcontextprotocol/server-github --env GITHUB_PERSONAL_ACCESS_TOKEN=your_token
```

### SSE Remote Service
```bash
/mcp add-sse square https://mcp.squareup.com/sse
```

## Configuration

You can configure MCP servers either:
- **Via commands**: Use `/mcp add` commands
- **Direct editing**: Modify `~/.metis/metis.json`

### Configuration Format

### Stdio Server
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "~/Documents"]
    }
  }
}
```

### With Environment Variables
```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "your_token_here"
      }
    }
  }
}
```

### SSE Server
```json
{
  "mcpServers": {
    "square": {
      "url": "https://mcp.squareup.com/sse"
    }
  }
}
```

## Important Notes

- **Restart Required**: After adding/removing servers, restart Magic CLI to load changes

## Links

- [MCP Official Documentation](https://modelcontextprotocol.io/)
- [MCP GitHub Repository](https://github.com/modelcontextprotocol)
- [Magic CLI Home](../README.md)
