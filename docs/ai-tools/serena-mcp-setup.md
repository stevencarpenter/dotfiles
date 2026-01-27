# Serena MCP Integration

## Overview

Serena is integrated into all AI development tools via the MCP (Model Context Protocol) sync system. This provides semantic code understanding powered by the JetBrains plugin across all tools.

## Architecture

### Master Configuration
- **Source**: `~/.config/mcp/mcp-master.json`
- **Purpose**: Single source of truth for MCP server definitions
- **Deployment**: Auto-synced to all tools via `scripts/sync-mcp-configs.py` (uv standalone script)

### Tool-Specific Contexts

Each tool receives a context-optimized Serena configuration:

| Tool | Context | Config Location | Format |
|------|---------|-----------------|--------|
| Claude Code | `claude-code` | `~/.claude.json` | MCP stdio |
| Codex | `codex` | `~/.codex/config.toml` | TOML |
| GitHub Copilot | `ide` | `~/.config/github-copilot/mcp.json` | JSON |
| Cursor | `ide` | `~/.cursor/mcp.json` | JSON |
| VSCode | `ide` | `~/.vscode/mcp.json` | JSON |
| OpenCode | `ide` | `~/.config/opencode/opencode.json` | JSON |
| Junie | `agent` | `~/.junie/mcp/mcp.json` | JSON |
| LM Studio | `desktop-app` | `~/.lmstudio/mcp.json` | JSON |

## Sync Process

### Automatic Sync
The sync happens automatically after `chezmoi apply`:

1. `chezmoi apply` deploys dotfiles
2. `.chezmoiscripts/run_after_sync-mcp.sh` executes
3. `scripts/sync-mcp-configs.py` runs (via `uv run --script`)
4. Configs generated from master with tool-specific contexts

### Manual Sync
```bash
uv run --script ~/.local/share/chezmoi/scripts/sync-mcp-configs.py
```

## Serena Configuration

### Global Settings
- **Location**: `~/.serena/serena_config.yml` (tracked in chezmoi)
- **Backend**: JetBrains plugin (requires IntelliJ with project open)
- **Token Counting**: Local tiktoken (accurate usage stats, no external API)
- **Dashboard**: http://localhost:24282/dashboard/

### Key Features
- `--project-from-cwd`: Auto-detects Serena projects
- `--mode=interactive,editing`: Full editing capabilities
- `--language-backend=JetBrains`: Uses paid plugin indexing

### Available Tools
- **Semantic Code**: `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`
- **Refactoring**: `replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol`
- **Memory**: `write_memory`, `read_memory`, `list_memories`
- **Project**: `activate_project`, `onboarding`

## Adding MCP Servers

### 1. Add to Master Config
Edit `~/.config/mcp/mcp-master.json`:
```json
{
  "servers": {
    "new-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@vendor/mcp-server"]
    }
  }
}
```

### 2. Run Sync
```bash
cd ~/.local/share/chezmoi
chezmoi apply
```

### 3. Restart Tools
Restart AI tools to pick up new configuration.

## Tool-Specific Notes

### Codex (TOML Format)
- Config: `~/.codex/config.toml`
- Sync: Automated context update for existing Serena config
- Manual: Use `codex mcp add` for new servers

### OpenCode (Nested MCP Format)
- Global: `~/.config/opencode/opencode.json`
- Project: `<project>/.opencode/opencode.json`
- Format: `{mcp: {server-name: {type: "local", command: [...]}}}}`
- Sync: Converts from master format automatically

### Cursor (SSE Support)
- Supports both stdio and SSE transports
- JetBrains server via SSE: `http://localhost:64342/sse`
- Other servers via stdio

## Troubleshooting

### Issue: Configs Overwritten After chezmoi apply
**Cause**: Sync script regenerates from master
**Solution**: Update master config, not individual tool configs

### Issue: Serena Not Connecting
**Cause**: IntelliJ not running or project not open
**Solution**: Open project in IntelliJ with Serena plugin active

### Issue: Wrong Context Used
**Cause**: Sync script context mapping
**Solution**: Update context in `scripts/sync-mcp-configs.py`, run sync

### Issue: Tool-Specific Config Needed
**Cause**: Master config is generic
**Solution**: Add tool-specific handling to sync script

## Maintenance

### Updating Serena
```bash
# Serena typically runs via the `scripts/serena-mcp` wrapper (prefers cached install, falls back to uvx).
~/.local/share/chezmoi/scripts/serena-mcp --help
```

### Checking Tool Status
```bash
# Codex
codex mcp list

# OpenCode
opencode mcp list

# Check logs
tail -f ~/.serena/logs/*.log
```

### Dashboard Monitoring
```bash
open http://localhost:24282/dashboard/
```

## Performance Tips

1. **Keep IntelliJ Open**: Serena uses its indexing
2. **Use Symbol Tools First**: Avoid reading entire files
3. **Project Memories**: Cache architectural decisions
4. **Token Tracking**: Monitor dashboard for usage patterns

## Security Notes

- Codex config encrypted in chezmoi (Age encryption)
- GITHUB_TOKEN referenced via environment variable
- Serena project configs in `.serena/project.yml`
- No secrets in master config

## References

- [MCP Protocol](https://modelcontextprotocol.io/)
- [Serena Documentation](https://oraios.github.io/serena/)
- [Chezmoi MCP Setup](./mcp-setup.md)
- [Sync Script](../../scripts/sync-mcp-configs.py)

---

**Last Updated**: 2026-01-27
**Maintainer**: dotfiles managed via chezmoi
