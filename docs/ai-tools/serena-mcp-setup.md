# Serena MCP Integration

## Overview

Serena is integrated into all AI development tools via the MCP (Model Context Protocol) sync system. This provides semantic code understanding powered by the JetBrains plugin across all tools.

## Architecture

### Master Configuration
- **Source**: `~/.config/mcp/mcp-master.json`
- **Purpose**: Single source of truth for MCP server definitions
- **Deployment**: Auto-synced to all tools via the `mcp_sync` uv app

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
3. `mcp_sync` runs (via `uv run --project`)
4. Configs generated from master with tool-specific contexts

### Manual Sync
```bash
uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs
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

**Semantic Code Navigation** (Recommended: Use these FIRST, before reading files)
- **`find_symbol(symbol_name, kind?, file_path?)`** - Find exact symbol definition across codebase
  - Fastest way to understand code - instant lookups instead of manual searching
  - Returns: File location, line number, context

- **`get_symbols_overview(file_path?)`** - Get hierarchical structure of current file or workspace
  - Classes, functions, types, imports organized by scope
  - Use case: Quickly understand codebase architecture

- **`find_referencing_symbols(symbol_name)`** - Find ALL usages of a symbol across entire codebase
  - Accuracy: Only matches code references (not comments/strings)
  - Use case: Impact analysis before refactoring, understanding scope

**Intelligent Refactoring** (Use when modifying code)
- **`replace_symbol_body(symbol_name, new_body)`** - Replace implementation of any symbol
  - Handles: Signature changes, overloads, multi-file updates automatically
  - Use case: Optimizations, bug fixes at the source

- **`insert_before_symbol(symbol_name, code)`** - Add code before a symbol
  - Use case: Setup, initialization, pre-conditions

- **`insert_after_symbol(symbol_name, code)`** - Add code after a symbol
  - Use case: Cleanup, post-processing, followup logic

**Architectural Memory** (Store knowledge for later iterations)
- **`write_memory(key, content)`** - Store architectural decisions, design patterns, issues
  - Examples: `"auth_pattern"`, `"db_schema_issues"`, `"refactor_blockers"`
  - Use case: Multiple agents working on same codebase share context

- **`read_memory(key)`** - Retrieve previously stored context before starting work
  - Use this at the beginning of any task

- **`list_memories()`** - View all stored architectural knowledge
  - Quick knowledge base of what's been analyzed

**Project Navigation**
- **`activate_project(project_name/path)`** - Switch projects (monorepo support)
- **`onboarding`** - Get project-specific guidance

**⚡ Performance Comparison:**
| Task | Serena | File Reading | Speed |
|------|--------|--------------|-------|
| Find function definition | `find_symbol()` | Open 5+ files | ~100x faster |
| Find all usages | `find_referencing_symbols()` | Grep/manual search | ~50x faster |
| Understand file structure | `get_symbols_overview()` | Scroll/read | ~20x faster |
| Multi-location refactor | `replace_symbol_body()` | Edit each file | Coordinated, accurate |

**👉 Agent Recommendation:** Use Serena tools as your PRIMARY code understanding method. Only read files for content you need to display or when Serena tools don't have the answer.

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
**Solution**: Update context in `mcp_sync`, run sync

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
- Sync app: `mcp_sync`

---

**Last Updated**: 2026-01-27
**Maintainer**: dotfiles managed via chezmoi
