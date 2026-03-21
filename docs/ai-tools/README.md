# AI Tools Configuration and Setup

This directory contains documentation for integrating AI-powered development tools into your workflow.

## Available Guides

### MCP (Model Context Protocol)
- **Documentation**: [MCP Setup Guide](./mcp-setup.md)
- Master MCP config synced to all AI tools via the `mcp_sync/` system

### Ralph + OpenCode
- **Documentation**: [Ralph + OpenCode Setup](./ralph-opencode-setup.md)
- Autonomous coding agent with local model support (LM Studio)
- Global wrapper script: `ralph-opencode` in `~/.local/bin/`

### Custom Terraform Instructions
- **Documentation**: [Terraform AI Instructions](./terraform-instructions.md)
- Best practices for AI tools when working with Terraform code

## Environment Variables

API keys and tokens live in `~/.config/zsh/.env` (encrypted via chezmoi). See the main [README](../../README.md) for the encryption workflow.
