# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A personal dotfiles repository managed by [Chezmoi](https://www.chezmoi.io/) for macOS. Secrets are
encrypted with age (key sourced from 1Password). The centerpiece is a custom Python tool (`mcp_sync/`) that syncs a
single master MCP config to 8+ AI development tools.

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

- **Master config**: `dot_config/mcp/mcp-master.json` — shared servers deployed to all machines
- **Machine overlays**: `dot_config/mcp/machine/{work,personal}.json` — machine-type-specific servers (e.g., AWS MCP on
  work only), deployed conditionally by chezmoi
- **Per-tool overrides**: `dot_config/mcp/overrides/` — JSON files that add/override servers for specific tools (e.g., `claude.json`, `copilot.json`)
- **Templates**: `mcp_sync/src/mcp_sync/templates/` — base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_generic_mcp_format()`, `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Merge order**: base template + master + machine overlay + per-tool overrides (later values win)

The sync runs automatically after `chezmoi apply` via `.chezmoiscripts/run_after_sync-mcp.sh.tmpl`. The hook
auto-detects the deployed machine overlay at `~/.config/mcp/machine/*.json` and passes it via `--machine-config`.

#### Machine-Type Gating

Configuration is gated by machine type via chezmoi's `.machine` variable (e.g., `personal-mac`, `work-mac`):

- **MCP shared**: `dot_config/mcp/mcp-master.json` — servers deployed to all machines
- **MCP work-only**: `dot_config/mcp/machine/work.json` — servers added on work machines (e.g., AWS MCP)
- **MCP personal-only**: `dot_config/mcp/machine/personal.json` — servers added on personal machines
- **Claude hooks**: `dot_claude/settings.json.tmpl` — hippo hook gated behind `{{ if hasPrefix "personal" .machine }}`
- **AeroSpace workspace assignments**: `dot_config/aerospace/aerospace.toml.tmpl` — separate `personal` / `work` blocks for `on-window-detected` rules; service-mode keybindings for personal layout scripts also gated
- **`.chezmoiignore`**: gates personal-only files (e.g., `workspace-5-comms.sh`, personal env / shell-function profiles) out of work deploys, and work-only files (e.g., `aws-config-gen/overrides.json`) out of personal deploys

### Key Directories

- `dot_config/mcp/` — Master MCP config and per-tool overrides
- `mcp_sync/` — Python sync tool (uv project, Python 3.14+, no runtime deps)
- `.chezmoiscripts/` — Post-apply hooks (MCP sync, macOS setup)
- `dot_config/zsh/` — Zsh config; `encrypted_dot_env` holds API keys
- `dot_config/nvim/` — Neovim config (LazyVim)
- `scripts/` — Utility scripts
- `docs/ai-tools/` — Setup guides for MCP, Copilot, etc.

### Tmux Status Bar Integration

A monitor script (`dot_config/tmux/scripts/claude-pane-monitor.sh`) runs every status-interval and sets per-window `@claude_state` options. The everforest color palette is defined inline (no theme plugin) so the monitor has full control over `window-status-format` and `window-status-current-format` with stoplight colors:

- **Green** (`#a7c080`) — actively working (braille spinner in pane title)
- **Yellow** (`#dbbc7f`) — waiting for input (pane title contains ✳)

Window names show `#{pane_title}` via `automatic-rename-format`, so tabs display Claude session names and state spinners instead of version numbers.

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

## Figma MCP Integration

> This is a developer tooling / dotfiles repository. It has **no UI framework, design system, component library, or styling layer**. If you receive a Figma URL in this context, it is almost certainly for reference (documentation, diagrams, or screenshots) — not for component implementation.

### What does not exist in this repo

- No frontend framework (React, Vue, Svelte, etc.)
- No CSS methodology or styling system
- No design tokens (colors, typography, spacing)
- No icon library or asset pipeline
- No component library or Storybook

### If Figma designs ever apply here

The only plausible Figma use-cases in this repo are:
1. **Architecture diagrams** — export as PNG/SVG to `docs/`
2. **Documentation screenshots** — place in `docs/` alongside the relevant `.md` file

### Figma MCP Required Flow (for any project, not this repo)

When implementing Figma designs in a separate project via these dotfiles' tooling:

1. Run `get_design_context` for the target node(s) to get structured representation
2. Run `get_screenshot` for visual reference
3. If `get_design_context` response is truncated, use `get_metadata` first to get the node map, then re-fetch specific nodes
4. IMPORTANT: Use localhost asset sources from the Figma MCP server directly — do not create placeholders
5. IMPORTANT: Do not install icon packages; use assets from the Figma payload
6. Translate React+Tailwind output into the target project's stack/conventions
7. Validate final UI against the Figma screenshot before marking complete
