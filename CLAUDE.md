# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A personal dotfiles repository managed by [Chezmoi](https://www.chezmoi.io/) for macOS and Arch Linux. Secrets are encrypted with age (key sourced from 1Password). The centerpiece is a custom Python tool (`mcp_sync/`) that syncs a single master MCP config to 8+ AI development tools.

## Commands

### MCP Sync (Python, in `mcp_sync/`)

All commands run from the repo root, not inside `mcp_sync/`:

```bash
# Lint
uv run --project mcp_sync --extra dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --extra dev ruff format --check mcp_sync/src mcp_sync/tests

# Test (all)
uv run --project mcp_sync --extra dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing

# Test (single file)
uv run --project mcp_sync --extra dev pytest mcp_sync/tests/test_sync_mcp_configs.py -v

# Run sync manually
uv run --project mcp_sync sync-mcp-configs
```

### Chezmoi

```bash
chezmoi diff          # Preview changes
chezmoi apply         # Apply dotfiles (triggers MCP sync automatically)
chezmoi apply -v      # Apply with verbose output
chezmoi add <file>    # Track a new file
chezmoi add --encrypt <file>  # Track with encryption
```

### Pre-commit

```bash
pre-commit run --all-files
```

## Architecture

### Chezmoi Naming Conventions

Source files use Chezmoi prefixes that transform on apply:
- `dot_` → `.` (e.g., `dot_config/` → `~/.config/`)
- `encrypted_` → decrypted via age
- `executable_` → chmod +x
- `.tmpl` suffix → Go template with variable substitution
- `run_after_` → script that runs after apply
- `run_once_` → script that runs only on first apply

### MCP Sync System (`mcp_sync/`)

The sync tool reads `dot_config/mcp/mcp-master.json` and generates tool-specific configs:

- **Master config**: `dot_config/mcp/mcp-master.json` — single source of truth for all MCP servers
- **Per-tool overrides**: `dot_config/mcp/overrides/` — JSON files that add/override servers for specific tools (e.g., `claude.json`, `copilot.json`)
- **Templates**: `mcp_sync/src/mcp_sync/templates/` — base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_generic_mcp_format()`, `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Deep merge**: base template + generated config + overrides, with later values winning

The sync runs automatically after `chezmoi apply` via `.chezmoiscripts/run_after_sync-mcp.sh`.

### Key Directories

- `dot_config/mcp/` — Master MCP config and per-tool overrides
- `mcp_sync/` — Python sync tool (uv project, Python 3.14+, no runtime deps)
- `.chezmoiscripts/` — Post-apply hooks (MCP sync, macOS setup)
- `dot_config/zsh/` — Zsh config; `encrypted_dot_env` holds API keys
- `dot_config/nvim/` — Neovim config (LazyVim)
- `scripts/` — Utility scripts
- `docs/ai-tools/` — Setup guides for MCP, Copilot, Ralph, etc.

### Encrypted Secrets

Environment variables live in `dot_config/zsh/encrypted_dot_env`. To update:
1. Edit `~/.config/zsh/.env`
2. Run `chezmoi add --encrypt ~/.config/zsh/.env`
3. Verify encryption: `head -3 ~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env` should show `-----BEGIN AGE ENCRYPTED FILE-----`

## CI

GitHub Actions (`.github/workflows/mcp-sync-ci.yml`) runs on changes to `mcp_sync/`:
- **Lint job**: ruff check + ruff format --check
- **Test job**: pytest with coverage

## Style

- Shell scripts: `set -euo pipefail`, bash
- Python: ruff for linting and formatting, no runtime dependencies, Python 3.14+
- Package manager: uv (not pip/poetry)
