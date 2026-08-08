# AI Tools Configuration and Setup

This directory contains documentation for integrating AI-powered development tools into your workflow.

## Available Guides

### MCP (Model Context Protocol)
- **Documentation**: [MCP Setup Guide](./mcp-setup.md)
- Master MCP config synced to all AI tools via the `mcp_sync/` system

### Claude Code + Tmux

- Experimental agent teams enabled (`teammateMode: tmux` in Claude Code settings)
- Tmux status bar shows Claude state with everforest stoplight colors (green=working, yellow=waiting)
- Monitor script: `home/.config/tmux/scripts/claude-pane-monitor.sh`
- [Tmux runtime lifecycle](./tmux-runtime-lifecycle.md): cwd inheritance, explicit tmux startup,
  socket/pane/process leaks, stateful plugin residue, and source-to-live verification

## Environment Variables

Personal API keys and tokens live in `~/.config/zsh/.personal.env`, rendered from 1Password
references by `op-render`. See the main [README](../../README.md) for the split personal/work secret
workflow.
