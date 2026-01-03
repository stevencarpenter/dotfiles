# MCP (Model Context Protocol) Setup Guide

## Overview

The Model Context Protocol (MCP) is an open protocol that enables AI assistants to securely access local and remote resources. This guide covers setting up MCP servers for use with Claude Desktop and other compatible AI tools.

## Configuration Files

### Location
- **General MCP Config**: `~/.config/mcp/mcp_config.json`
- **Claude Desktop Config**: `~/.config/mcp/claude_desktop_config.json`

### Installation

Use `chezmoi` to apply the MCP configuration from this dotfiles repository:

```bash
chezmoi apply
```

This will deploy the configuration files to `~/.config/mcp/` and automatically sync them to all AI tools.

## Available MCP Servers

### 1. GitHub Server
Access and interact with GitHub repositories, issues, and pull requests.

**Environment Variable Required:**
```bash
export GITHUB_TOKEN="ghp_your_personal_access_token"
```

**Create Token:**
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with scopes: `repo`, `read:org`, `read:user`
3. Add to your `~/.zshenv` or `~/.zshrc`

### 2. Filesystem Server
Read and write files within specified directories.

**Default Access:**
- `~/projects/` - Your main projects directory
- `~/.local/share/chezmoi/` - This dotfiles repository

**Security Note:** Only directories explicitly listed in the configuration are accessible.

### 3. Git Server
Perform git operations on repositories.

**Features:**
- Read git log and history
- View diffs and commits
- Check repository status
- No write operations for safety

### 4. Postgres Server
Query and interact with PostgreSQL databases.

**Configuration:**
Update the connection string in `claude_desktop_config.json`:
```json
{
  "postgres": {
    "command": "npx",
    "args": [
      "-y",
      "@modelcontextprotocol/server-postgres",
      "postgresql://username:password@localhost:5432/dbname"
    ]
  }
}
```

### 5. Puppeteer Server
Automate browser interactions for web scraping and testing.

**Use Cases:**
- Web scraping
- Automated testing
- Screenshot capture
- Form filling

### 6. Sequential Thinking Server
Enhanced reasoning capabilities for complex problems.

**Features:**
- Step-by-step problem solving
- Chain of thought reasoning
- Complex analysis tasks

### 7. SQLite Server
Work with SQLite databases.

**Configuration:**
```bash
export DATABASE_PATH="${HOME}/.local/share/databases"
```

Create the directory:
```bash
mkdir -p ~/.local/share/databases
```

### 8. Brave Search Server
Perform web searches using Brave Search API.

**Setup:**
1. Get API key from [Brave Search API](https://brave.com/search/api/)
2. Add to environment:
```bash
export BRAVE_API_KEY="your_brave_api_key"
```

## Installing MCP Servers

All MCP servers are installed on-demand via `npx`. They will be automatically downloaded when first used.

To pre-install all servers:

```bash
npm install -g @modelcontextprotocol/server-github
npm install -g @modelcontextprotocol/server-filesystem
npm install -g @modelcontextprotocol/server-git
npm install -g @modelcontextprotocol/server-postgres
npm install -g @modelcontextprotocol/server-puppeteer
npm install -g @modelcontextprotocol/server-sequential-thinking
npm install -g @modelcontextprotocol/server-sqlite
npm install -g @modelcontextprotocol/server-brave-search
```

## Using with Claude Desktop

1. **Install Claude Desktop**: Download from [claude.ai](https://claude.ai/)

2. **Configuration**: The config file is already set up at `~/.config/mcp/claude_desktop_config.json`

3. **Restart Claude Desktop**: Close and reopen the application

4. **Verify**: Open Claude Desktop and check that MCP servers appear in the available tools

## Customizing MCP Servers

### Adding Custom Servers

Edit `~/.config/mcp/mcp_config.json` to add custom MCP servers:

```json
{
  "mcpServers": {
    "my-custom-server": {
      "command": "node",
      "args": ["/path/to/server.js"],
      "env": {
        "CUSTOM_VAR": "value"
      }
    }
  }
}
```

### Modifying Filesystem Access

To grant access to additional directories, edit the `filesystem` server args:

```json
{
  "filesystem": {
    "command": "npx",
    "args": [
      "-y",
      "@modelcontextprotocol/server-filesystem",
      "${HOME}/projects",
      "${HOME}/.local/share/chezmoi",
      "${HOME}/new-directory"
    ]
  }
}
```

## Troubleshooting

### MCP Servers Not Appearing

1. Check Claude Desktop logs:
   - macOS: `~/Library/Logs/Claude/`
   - Linux: `~/.config/Claude/logs/`

2. Verify environment variables are set:
```bash
echo $GITHUB_TOKEN
```

3. Test server manually:
```bash
npx -y @modelcontextprotocol/server-github
```

### Permission Errors

Ensure directories have proper permissions:
```bash
chmod 700 ~/.config/mcp
chmod 600 ~/.config/mcp/*.json
```

### NPX Installation Issues

Update npm and node:
```bash
npm install -g npm@latest
```

Or install servers globally as shown above.

## Security Best Practices

1. **Token Security**: Never commit tokens to git. Use environment variables.

2. **Filesystem Access**: Only grant access to necessary directories.

3. **Database Credentials**: Use environment variables for connection strings.

4. **Regular Updates**: Keep MCP servers updated:
```bash
npm update -g @modelcontextprotocol/server-*
```

5. **Audit Access**: Regularly review which servers have access to what resources.

## Additional Resources

- [MCP Official Documentation](https://modelcontextprotocol.io/)
- [MCP Server Repository](https://github.com/modelcontextprotocol/servers)
- [Claude Desktop Documentation](https://claude.ai/docs)
