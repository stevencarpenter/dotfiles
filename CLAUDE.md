# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a comprehensive dotfiles repository for macOS and Arch Linux systems, managed with **Chezmoi** and **age encryption**. It centralizes shell configuration, development tool setups, AI tool integration (MCP), and platform-specific automation scripts.

## Common Commands

### Chezmoi Dotfile Management

```bash
# Preview changes (dry-run) - shows what would be applied
chezmoi diff

# Apply all dotfiles
chezmoi apply

# Apply with verbose output
chezmoi apply -v

# Add a new file to be managed
chezmoi add ~/.config/some-tool/config

# Add a file with encryption
chezmoi add --encrypt ~/.config/secrets/token

# Edit a managed file (opens source, applies on save)
chezmoi edit ~/.config/zsh/.zshrc

# Re-add a modified file
chezmoi re-add ~/.config/some-tool/config

# Update from remote repository
chezmoi update

# View managed files
chezmoi managed

# Check for differences
chezmoi status
```

### MCP Configuration Sync

```bash
# MCP configs are synced automatically after chezmoi apply
# Manual sync (if needed):
~/.local/share/chezmoi/scripts/sync-mcp-configs.sh

# Edit master MCP config
chezmoi edit ~/.config/mcp/mcp-master.json
```

### Pre-commit Hooks

```bash
# Run all pre-commit checks
pre-commit run --all-files

# Run specific hook
pre-commit run {hook_id} --all-files
```

### Platform Setup

```bash
# macOS: Chezmoi scripts run automatically on apply
# Manual brew bundle (if needed):
brew bundle --file=~/.Brewfile

# Arch Linux: Full setup
bash ~/.local/share/chezmoi/arch/setup_arch.sh
```

### Git Worktree Management

```bash
git wt list       # List worktrees
git mkwt <name>   # Create new worktree
git rmwt <name>   # Remove worktree
```

## Project Architecture

### Directory Structure

- **`dot_config/`** - XDG-compliant config directory (zsh, nvim, git, tmux, mcp, ralph, opencode, etc.)
- **`dot_local/bin/`** - User executables (ralph-opencode wrapper, custom scripts). This
- **`dot_zshenv`** - Root zsh environment file
- **`dot_Brewfile`** - Homebrew packages, casks, and fonts
- **`.chezmoiscripts/`** - Scripts that run during `chezmoi apply`
    - `run_after_sync-mcp.sh` - Syncs MCP configs after apply
    - `darwin/run_once_setup-macos.sh` - One-time macOS setup
- **`arch/`** - Arch Linux-specific setup (setup script)
- **`scripts/`** - Utility scripts (MCP config sync, etc.)
- **`docs/ai-tools/`** - Detailed setup guides for AI tools
- **`.chezmoiignore`** - Files to ignore during apply
- **`.chezmoiencrypt.toml`** - Encryption configuration for age
- **`.pre-commit-config.yaml`** - Pre-commit hook definitions

### Key Design Patterns

#### 1. Master MCP Configuration (Single Source of Truth)

The repository uses a **master MCP config** pattern:

- **Source**: `dot_config/mcp/mcp-master.json` - single, authoritative config
- **Targets**: Automatically synced to multiple AI tools via `.chezmoiscripts/run_after_sync-mcp.sh`
    - `~/.config/mcp/mcp_config.json` (Generic MCP format)
    - `~/.config/github-copilot/mcp.json` (GitHub Copilot CLI)
    - `~/.config/.copilot/mcp-config.json` (GitHub Copilot)
    - `~/.config/github-copilot/intellij/mcp.json` (IntelliJ)
- **Automation**: `scripts/sync-mcp-configs.sh` performs format transformation
- **Chezmoi Integration**: Sync runs automatically after `chezmoi apply`
- **MCP Servers**: filesystem, memory, sequential-thinking, railway, github, supabase

**Note: Claude Code uses a separate plugin system** - see "Claude Code" section below.

#### 2. XDG Base Directory Compliance

Uses modern Linux/macOS conventions:

- `XDG_CONFIG_HOME=~/.config` - Configuration files
- `XDG_DATA_HOME=~/.local/share` - Data files
- `ZDOTDIR=~/.config/zsh` - Zsh configuration directory
- Reduces clutter in home directory

#### 3. Shell Configuration Layering

Zsh configuration is organized in layers:

- **`.zshenv`** (minimal, always sourced) - Base environment, XDG setup, PATH
- **`.zprofile`** (login shell) - Tool initializations, AWS SSO, functions
- **`.zshrc`** (interactive shell) - Aliases, completions, prompt, z4h framework
- **`.env`** (encrypted) - Sensitive environment variables sourced at runtime
- **Z4H Framework** - Zsh4humans for modern, fast zsh configuration

#### 4. Chezmoi-Based File Management

Uses Chezmoi for dotfile management with age encryption:

- **Naming conventions**: `dot_` prefix for dotfiles, `private_` for permissions, `encrypted_` for encrypted files
- **Encryption**: Files with `encrypted_` prefix are decrypted on apply (configured via `~/.config/chezmoi/chezmoi.toml`)
- **Templates**: `.tmpl` suffix for templated files
- **Scripts**: `.chezmoiscripts/` directory for automation
- **Config**: `suffix = ""` in chezmoi.toml prevents redundant `.age` extension when adding encrypted files

#### 5. Environment Variable Management

Sensitive configuration is encrypted and managed:

- **Source**: `dot_config/zsh/encrypted_dot_env` - encrypted with age, stored in repo
- **Target**: `~/.config/zsh/.env` - decrypted on apply, sourced by shell
- **Storage**: Age encryption key backed up in 1Password (`~/.config/chezmoi/key.txt`)
- **Required vars**: GITHUB_TOKEN, GITHUB_PERSONAL_ACCESS_TOKEN, OPENAI_API_KEY, SUPABASE_PROJECT_REF, BRAVE_API_KEY, CONTEXT7_API_KEY, NPM_TOKEN, OPENROUTER_TOKEN, ATLASSIAN_API_TOKEN
- **Note**: `GITHUB_PERSONAL_ACCESS_TOKEN` is set as an alias to `GITHUB_TOKEN` in `.zprofile` for Claude Code compatibility

### Chezmoi Scripts

Scripts in `.chezmoiscripts/` run during `chezmoi apply`:

- **`run_after_sync-mcp.sh`** - Syncs MCP config to all AI tools after apply
- **`darwin/run_once_setup-macos.sh`** - One-time macOS setup (brew checks, rustup)

### Pre-commit Checks

Configured in `.pre-commit-config.yaml`:

- YAML/JSON/TOML validation
- File size limits
- Case conflict detection
- Private key detection
- AWS credentials detection

### Tool Integrations

#### Neovim

- **Location**: `dot_config/nvim/`
- **Setup**: LazyVim (Lua-based, lazy loading)
- **Files**: `init.lua`, `lazyvim.json`, `lazy-lock.json`

#### Git

- **Location**: `dot_config/git/config`
- **Worktree Aliases**: Custom aliases for git worktree management

#### Tmux

- **Location**: `dot_config/tmux/tmux.conf`
- **Plugins**: TPM (Tmux Plugin Manager), tmux-resurrect (session persistence)
- **Features**: Extensive key bindings, status bar customization

#### Mise (Version Manager)

- **Location**: `dot_config/mise/`
- **Purpose**: Manages runtime versions (Node, Python, Go, etc.)

#### GitHub Copilot & MCP

- Integrated via master MCP config
- GitHub server for API access (requires GITHUB_TOKEN)
- Sequential thinking server for complex reasoning
- Filesystem access limited to specific directories

#### Ralph + OpenCode

- **Location**: `dot_config/ralph/` and `dot_config/opencode/`
- **Purpose**: Autonomous coding agent with local model support (LM Studio)
- **Components**:
    - `ralph.json.tmpl` - Ralph loop configuration (iterations, guards, safe mode)
    - `opencode.json.tmpl` - OpenCode agent configuration (model, providers)
    - `rules.toml` - Permission rules for safe mode (filesystem, shell, network)
- **Wrapper Script**: `dot_local/bin/executable_ralph-opencode` → `~/.local/bin/ralph-opencode`
- **State Location**: `~/.local/state/ralph/` (logs, metrics, per-repo state)
- **Commands**:
    ```bash
    ralph-opencode doctor           # System health check
    ralph-opencode config show      # Show resolved configuration
    ralph-opencode --prd ./prd.json # Run single iteration
    ralph-opencode --prd ./prd.json --until-complete --safe  # Overnight run
    ```
- **Documentation**: `docs/ai-tools/ralph-opencode-setup.md`

#### Claude Code

Claude Code uses a **separate plugin system** that is NOT managed by the master MCP config sync:

- **Location**: `~/.claude/` - settings, plugins, history
- **Plugin System**: Official plugins from `claude-plugins-official` marketplace
- **Config Files**:
    - `~/.claude/settings.json` - global settings and enabled plugins
    - `~/.claude/plugins/installed_plugins.json` - installed plugin metadata
    - `~/.claude/plugins/cache/` - cached plugin files including `.mcp.json` configs
- **Enabled Plugins**: context7, github, supabase, greptile, playwright, feature-dev, code-review, commit-commands, frontend-design, security-guidance, LSP servers (rust-analyzer, typescript, pyright)
- **GitHub Plugin**: Uses HTTP MCP at `https://api.githubcopilot.com/mcp/` with `GITHUB_PERSONAL_ACCESS_TOKEN`
- **Project Settings**: `.claude/settings.local.json` in project root for per-project permissions

**Important**: To modify Claude Code's MCP servers, you must use the `/mcp` command within Claude Code or edit the plugin cache directly. The master MCP config sync does not affect Claude Code.

### macOS Setup

- **Brewfile**: `dot_Brewfile` - Comprehensive list of packages, casks, fonts, and formulae
- **Setup script**: `.chezmoiscripts/darwin/run_once_setup-macos.sh`
    - Runs brew health checks
    - Installs rustup if not present
- **Key tools installed**: zsh, git, tmux, neovim, ripgrep, fzf, jq, yq, bat, fd, zoxide, direnv, yazi, chezmoi, age

## Important Files

### Configuration

- `dot_config/zsh/dot_zshrc` - Main interactive shell config with aliases, completions, tool integrations
- `dot_config/mcp/mcp-master.json` - Master MCP server configuration (source of truth)
- `dot_config/git/config` - Git configuration with worktree management
- `dot_config/nvim/init.lua` - Neovim initialization
- `dot_config/ralph/ralph.json.tmpl` - Ralph loop configuration (global defaults)
- `dot_config/opencode/opencode.json.tmpl` - OpenCode agent configuration (models, providers)
- `dot_config/opencode/rules.toml` - Safe mode permission rules for unattended runs

### Encryption & Security

- `.chezmoiencrypt.toml` - Defines which files are encrypted with age
- `~/.config/chezmoi/key.txt` - Age private key (NOT in repo, backed up in 1Password)

### Automation

- `scripts/sync-mcp-configs.sh` - Syncs master MCP config to all AI tools
- `.chezmoiscripts/run_after_sync-mcp.sh` - Runs sync after chezmoi apply
- `.chezmoiscripts/darwin/run_once_setup-macos.sh` - One-time macOS setup
- `dot_local/bin/executable_ralph-opencode` - Global wrapper for Ralph + OpenCode

### Setup & Installation

- `dot_Brewfile` - Homebrew packages, casks, and fonts
- `arch/setup_arch.sh` - Arch Linux setup automation

### Documentation

- `README.md` - Main repository documentation
- `docs/ai-tools/` - Setup guides for GitHub Copilot, IntelliJ, Claude/MCP, OpenAI Codex, Ralph/OpenCode
- `docs/archive/` - Legacy documentation

## Workflow Notes

### Adding or Modifying MCP Servers

**For Copilot and other tools (via master config):**

1. Edit `dot_config/mcp/mcp-master.json` (the master config)
2. Run `chezmoi apply` - sync script runs automatically
3. Or manually run `~/.local/share/chezmoi/scripts/sync-mcp-configs.sh`
4. Verify the config is synced to all tool locations

**For Claude Code (separate plugin system):**

1. Use `/mcp` command in Claude Code to manage plugins
2. Or enable/disable plugins via `/mcp enable <plugin>` and `/mcp disable <plugin>`
3. Plugin configs are stored in `~/.claude/plugins/cache/`
4. Note: Claude Code uses `GITHUB_PERSONAL_ACCESS_TOKEN` (aliased from `GITHUB_TOKEN` in `.zprofile`)

### Configuring Ralph + OpenCode

**Global Configuration (defaults for all repos):**

1. Edit templates in chezmoi source:
   - `dot_config/ralph/ralph.json.tmpl` - Loop settings, safe mode, secrets
   - `dot_config/opencode/opencode.json.tmpl` - Model, providers, tools
   - `dot_config/opencode/rules.toml` - Safe mode permission rules
2. Run `chezmoi apply` to deploy
3. Verify with `ralph-opencode config show`

**Per-Repo Overrides:**

1. Create `ralph.json` in the repo root:
   ```json
   {
     "opencode": { "model": "different-model" },
     "safeMode": { "enabled": true }
   }
   ```
2. Repo config overrides global; CLI flags override both

**Using LM Studio (local models):**

1. Start LM Studio, load a model, enable API server (port 1234)
2. Verify: `ralph-opencode doctor`
3. Run: `ralph-opencode --prd ./prd.json`

**Overnight Runs (safe mode):**

```bash
ralph-opencode --repo /path/to/project --prd ./prd.json \
    --until-complete --safe --max-hours 8
```

### Installing New Tools

1. Add to `dot_Brewfile` (if on macOS)
2. Run `brew bundle --file=~/.Brewfile`
3. Or manually run `brew install <package>`
4. Add any configuration: `chezmoi add ~/.config/<tool>/config`
5. Run `chezmoi apply` to verify

### Adding Encrypted Files

1. Add file with encryption: `chezmoi add --encrypt ~/.config/secrets/token`
2. File will be stored with `encrypted_` prefix in source state (e.g., `encrypted_token`)
3. Decrypted automatically on `chezmoi apply`
4. **Important**: Always verify the source file is encrypted before committing:
   ```bash
   head -3 ~/.local/share/chezmoi/path/to/encrypted_file
   # Should show: -----BEGIN AGE ENCRYPTED FILE-----
   ```

### Updating Encrypted Files

1. Edit the decrypted target file directly: `nvim ~/.config/zsh/.env`
2. Re-add with encryption: `chezmoi add --encrypt ~/.config/zsh/.env`
3. Verify encryption before committing

### New Machine Setup

1. Install chezmoi and age: `brew install chezmoi age`
2. Create age key from 1Password backup: `mkdir -p ~/.config/chezmoi && <paste key> > ~/.config/chezmoi/key.txt && chmod 600 ~/.config/chezmoi/key.txt`
3. Initialize chezmoi: `chezmoi init git@github.com:stevencarpenter/dotfiles.git`
4. Apply dotfiles: `chezmoi apply`

### Development Container Support

- Dev container setup in `dot_config/dev-container/`
- Includes user/group mapping for container development
- Environment variable injection supported

## Pre-commit and Testing

- Run `pre-commit run --all-files` before committing
- Checks for YAML/JSON/TOML syntax, private keys, AWS credentials
- Prevents accidental secret commits
- All checks must pass before merge
