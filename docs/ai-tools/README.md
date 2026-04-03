# AI Tools Configuration and Setup

This directory contains documentation for integrating AI-powered development tools into your workflow.

## Available Guides

### MCP (Model Context Protocol)
- **Documentation**: [MCP Setup Guide](./mcp-setup.md)
- Master MCP config synced to all AI tools via the `mcp_sync/` system

### Custom Terraform Instructions
- **Documentation**: [Terraform AI Instructions](./terraform-instructions.md)
- Best practices for AI tools when working with Terraform code

### Claude Code + Tmux
- Experimental agent teams enabled (`teammateMode: auto` in Claude Code settings)
- Tmux status bar shows Claude state with everforest stoplight colors (green=idle, yellow=working)
- Monitor script: `dot_config/tmux/scripts/claude-pane-monitor.sh`

## Environment Variables

API keys and tokens live in `~/.config/zsh/.env` (encrypted via chezmoi). See the main [README](../../README.md) for the encryption workflow.
