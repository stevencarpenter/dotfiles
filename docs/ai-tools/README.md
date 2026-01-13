# AI Tools Configuration and Setup

This directory contains comprehensive documentation and configuration files for integrating AI-powered development tools into your workflow.

## Available Configurations

### MCP (Model Context Protocol)
- **Location**: `~/.config/mcp/`
- **Documentation**: [MCP Setup Guide](./mcp-setup.md)
- Model Context Protocol configurations for AI assistants like Claude Desktop

### IntelliJ IDEA Copilot
- **Documentation**: [IntelliJ IDEA Copilot Setup](./intellij-copilot-setup.md)
- Complete setup and configuration guide for GitHub Copilot in IntelliJ IDEA

### Copilot CLI
- **Documentation**: [Copilot CLI Setup](./copilot-cli-setup.md)
- Command-line interface for GitHub Copilot integration

### OpenAI Codex CLI
- **Documentation**: [OpenAI Codex CLI Setup](./openai-codex-cli-setup.md)
- Setup and usage guide for OpenAI Codex CLI integration

### Custom Terraform Instructions
- **Documentation**: [Terraform AI Instructions](./terraform-instructions.md)
- Custom instructions for AI tools when working with Terraform code

### Ralph + OpenCode
- **Location**: `~/.config/ralph/` and `~/.config/opencode/`
- **Documentation**: [Ralph + OpenCode Setup](./ralph-opencode-setup.md)
- Autonomous coding agent with local model support (LM Studio)
- Global wrapper script: `ralph-opencode` in `~/.local/bin/`

## Quick Start

1. **Install MCP Servers**: Follow the [MCP Setup Guide](./mcp-setup.md)
2. **Configure IDE**: Set up [IntelliJ IDEA Copilot](./intellij-copilot-setup.md)
3. **Enable CLI Tools**: Install [Copilot CLI](./copilot-cli-setup.md)
4. **Set up Ralph + OpenCode**: Follow the [Ralph + OpenCode Setup](./ralph-opencode-setup.md)
5. **Custom Instructions**: Apply [Terraform Instructions](./terraform-instructions.md)

## Environment Variables

The following environment variables should be set in your shell configuration:

```bash
# GitHub Copilot
export GITHUB_TOKEN="your_github_personal_access_token"

# OpenAI (if using Codex CLI)
export OPENAI_API_KEY="your_openai_api_key"

# Brave Search (optional for MCP)
export BRAVE_API_KEY="your_brave_api_key"

# Ralph + OpenCode (optional, can use config file instead)
export RALPH_MODEL="lmstudio/qwen2.5-coder-32b-instruct"
export RALPH_BASE_URL="http://127.0.0.1:1234/v1"
export OPENROUTER_TOKEN="your_openrouter_token"  # For cloud models
```

Add these to your `~/.zshrc` or `~/.zshenv` file (or better: encrypted in `~/.config/zsh/.env`).

## Support

For issues or questions:
- Check individual documentation files
- Review configuration examples in `~/.config/mcp/`
- Consult official documentation for each tool
