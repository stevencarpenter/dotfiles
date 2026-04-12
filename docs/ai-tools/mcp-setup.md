# MCP (Model Context Protocol) Setup Guide

## Overview

This dotfiles repo uses a **single master MCP config** that syncs to all AI development tools automatically. The sync is handled by the `mcp_sync/` Python tool, which runs after every `chezmoi apply`.

## How It Works

1. **Master config**: `dot_config/mcp/mcp-master.json` — single source of truth
2. **Per-tool overrides**: `dot_config/mcp/overrides/` — JSON files that add/override servers for specific tools (e.g., `claude.json`, `copilot.json`)
3. **Sync tool**: `mcp_sync/` transforms and merges configs into each tool's expected format
4. **Auto-sync**: `.chezmoiscripts/run_after_sync-mcp.sh` runs the sync after `chezmoi apply`

## Current MCP Servers

The master config (`dot_config/mcp/mcp-master.json`) includes:

| Server | Package | Purpose |
|--------|---------|---------|
| **GitHub** | `github-mcp-server` (Homebrew, invoked via `sh -c` wrapper that sources the PAT from `gh auth token` at launch) | Repository operations, PR management, issue handling |
| **Railway** | `@railway/mcp-server` | Deployment status, logs, environment management |
| **AWS CCAPI** | `awslabs.ccapi-mcp-server` | AWS resource management (read-only by default) |

Additional servers may be added per-tool via override files in `dot_config/mcp/overrides/`.

## Sync Targets

After `chezmoi apply`, configs are synced to:

| Tool | Destination |
|------|-------------|
| GitHub Copilot | `~/.config/.copilot/mcp-config.json` |
| GitHub Copilot CLI | `~/.config/github-copilot/mcp.json` |
| IntelliJ Copilot | `~/.config/github-copilot/intellij/mcp.json` |
| Cursor | `~/.config/cursor/mcp.json` (+ legacy `~/.cursor/` mirror) |
| VS Code | `~/.vscode/mcp.json` |
| Junie | `~/.junie/mcp/mcp.json` |
| LM Studio | `~/.lmstudio/mcp.json` |
| Codex CLI | `~/.codex/config.toml` |
| Claude Code | `~/.claude.json` |
| OpenCode | `~/.config/opencode/opencode.json` |
| Generic MCP | `~/.config/mcp/mcp_config.json` |

## Adding a New MCP Server

Edit the master config:

```bash
chezmoi edit ~/.config/mcp/mcp-master.json
chezmoi apply  # Sync runs automatically
```

To add a server only for a specific tool, create or edit an override file:

```bash
# Example: add a server only for Claude Code
nvim dot_config/mcp/overrides/claude.json
chezmoi apply
```

## Manual Sync

```bash
uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs
```

## Authentication / Credentials

Different servers use different credential sources:

- **GitHub**: No env var required. The `sh -c` wrapper in `mcp-master.json` calls `gh auth token` at spawn time and exports `GITHUB_PERSONAL_ACCESS_TOKEN` only into the server process. Token lives in the OS keychain (`gh auth login`); fails fast with a useful message if `gh` isn't authenticated. No long-lived shell env var.
- **Other servers (Railway, AWS, etc.)**: reference environment variables (e.g., `${RAILWAY_TOKEN}`) expanded by the MCP client at server-launch time. These are stored encrypted in `dot_config/zsh/encrypted_dot_env` and sourced at shell startup.

To rotate the GitHub token, run `gh auth refresh` or `gh auth login` — no dotfiles change required.

## Troubleshooting

**Sync not running after apply?**
- Verify `uv` is installed: `which uv`
- Check the sync script: `cat ~/.local/share/chezmoi/.chezmoiscripts/run_after_sync-mcp.sh`

**Server not appearing in a tool?**
- Check if the tool has an override that excludes it: `ls dot_config/mcp/overrides/`
- Verify the tool's config was written: check the destination path from the table above

**Testing sync changes:**
```bash
uv run --project mcp_sync --extra dev pytest mcp_sync/tests -v
```
