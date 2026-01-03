# MCP Server Setup Guide

> **Note:** This documentation is archived. For current MCP setup instructions, see [docs/ai-tools/mcp-setup.md](../ai-tools/mcp-setup.md).

## Overview

This guide covers setting up Model Context Protocol (MCP) servers to work with:
- **IntelliJ IDEA Copilot Extension**
- **Copilot CLI**
- **OpenAI Codex CLI**

## Configuration Location

Configuration files are managed through your dotfiles using chezmoi:
- **Main config**: `~/.config/mcp/mcp.json`
- **Docker fallback**: `~/.config/mcp/mcp.docker.json`
- **Custom instructions**: `~/.config/mcp/terraform-instructions/`

## MCP Servers

### 1. Terraform MCP Server
**Purpose**: Infrastructure-as-code assistant for Terraform configurations

**Configuration**:
```json
"terraform": {
  "command": "uvx",
  "args": ["--from", "hashicorp/terraform-mcp-server", "terraform-mcp-server"],
  "env": {
    "TERRAFORM_MCP_INSTRUCTIONS_PATH": "${HOME}/.config/mcp/terraform-instructions",
    "TF_LOG": "INFO"
  }
}
```

**Custom Instructions**:
Your custom Terraform instructions are loaded from `~/.config/mcp/terraform-instructions/`:
- `system-prompt.txt` - Core guidance for Terraform assistance
- `best-practices.md` - Best practices and standards
- `config.yaml` - Configuration for instruction loading

### 2. Memory MCP Server
**Purpose**: Persistent knowledge graph for maintaining context across sessions

**Configuration**:
```json
"memory": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-memory"]
}
```

### 3. Sequential Thinking MCP Server
**Purpose**: Step-by-step reasoning for complex problem solving

**Configuration**:
```json
"sequential-thinking": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
}
```

### 4. Git MCP Server
**Purpose**: Git repository interaction and automation

**Configuration**:
```json
"git": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-git"]
}
```

### 5. AWS Knowledge MCP Server
**Purpose**: AWS service documentation and best practices

**Configuration**:
```json
"aws-knowledge-mcp-server": {
  "command": "uvx",
  "args": ["fastmcp", "run", "https://knowledge-mcp.global.api.aws"]
}
```

## Setup Instructions

### 1. Apply Dotfiles with Chezmoi
```bash
chezmoi apply
```

This automatically deploys `~/.config/mcp/mcp.json` and related files.

### 2. IntelliJ IDEA Copilot Extension

1. Open IntelliJ IDEA Settings/Preferences
2. Navigate to **Tools > Copilot**
3. Enable MCP servers
4. The extension will automatically discover `~/.config/mcp/mcp.json`

### 3. Copilot CLI

```bash
# Verify configuration
copilot config show

# The CLI automatically checks:
# - ~/.config/mcp/mcp.json
# - $COPILOT_CONFIG_DIR/mcp.json
```

### 4. OpenAI Codex CLI

```bash
# Set configuration path (optional)
export OPENAI_CONFIG_HOME=~/.config

# The CLI will load MCP configuration from:
# - ~/.config/mcp/mcp.json
```

## Testing

### Test Individual Servers

```bash
# Test Terraform server
uvx --from hashicorp/terraform-mcp-server terraform-mcp-server

# Test Memory server
npx -y @modelcontextprotocol/server-memory

# Test Sequential Thinking server
npx -y @modelcontextprotocol/server-sequential-thinking

# Test Git server
npx -y @modelcontextprotocol/server-git
```

### Verify Configuration Loading

```bash
# Check Terraform instructions path
echo $TERRAFORM_MCP_INSTRUCTIONS_PATH

# List Terraform instructions
ls -la ~/.config/mcp/terraform-instructions/

# Verify all config files exist
ls -la ~/.config/mcp/
```

### Check Tool Integration

```bash
# IntelliJ - Check plugin logs
# Copilot CLI - Run with debug flag
copilot --verbose

# OpenAI Codex - Check environment
env | grep -i config
```

## Troubleshooting

### Servers Not Loading

1. **Verify chezmoi deployed files**:
   ```bash
   ls -la ~/.config/mcp/
   chezmoi managed | grep mcp
   ```

2. **Check NPX/UVX installation**:
   ```bash
   which npx
   which uvx
   uv --version
   ```

3. **Test individual server startup**:
   ```bash
   npx -y @modelcontextprotocol/server-memory
   # Should start without errors
   ```

### Custom Terraform Instructions Not Loading

1. **Verify environment variable**:
   ```bash
   echo $TERRAFORM_MCP_INSTRUCTIONS_PATH
   ```

2. **Check file permissions**:
   ```bash
   ls -la ~/.config/mcp/terraform-instructions/
   ```

3. **Inspect server logs** in your tool:
   - IntelliJ: View plugin logs
   - Copilot CLI: Use `--verbose` flag
   - Codex CLI: Check stderr output

### Docker Fallback Configuration

If you need to use Docker instead of NPX/UVX:

```bash
# Copy docker config
cp ~/.config/mcp/mcp.docker.json ~/.config/mcp/mcp.json

# Ensure Docker is running
docker --version
```

## Environment Variables

Key environment variables for MCP configuration:

```bash
# Terraform MCP Server
TERRAFORM_MCP_INSTRUCTIONS_PATH=~/.config/mcp/terraform-instructions
TF_LOG=INFO

# Copilot CLI
COPILOT_CONFIG_DIR=~/.config

# OpenAI Config
OPENAI_CONFIG_HOME=~/.config
```

## Documentation References

- [Terraform MCP Server](https://github.com/modelcontextprotocol/servers/blob/main/src/terraform/README.md)
- [MCP Memory Server](https://github.com/modelcontextprotocol/servers)
- [MCP Sequential Thinking](https://github.com/modelcontextprotocol/servers/blob/main/src/sequentialthinking/README.md)
- [MCP Git Server](https://github.com/modelcontextprotocol/servers/blob/main/src/git/README.md)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review individual server documentation
3. Check tool-specific logs and debug output
