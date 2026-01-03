# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a comprehensive dotfiles repository for macOS and Arch Linux systems, managed with **Stow**. It centralizes shell configuration, development tool
setups, AI tool integration (MCP), and platform-specific automation scripts. The repository is currently on a `chezmoi` branch exploring migration from Stow to
Chezmoi with age encryption.

## Common Commands

### Stow-Based Dotfile Management

```bash
# Preview changes (dry-run) - shows what symlinks would be created
cd ~/.dotfiles && make debug
# or: stow -nvvv home

# Apply all dotfiles (creates symlinks)
cd ~/.dotfiles && make stow

# Reapply symlinks (useful after manual changes)
make restow

# Remove all symlinks
make unstow
# or: stow -D home

# Show help for make targets
make help
```

### MCP Configuration Sync

```bash
# Manually sync master MCP config to all tools
~/.dotfiles/scripts/sync-mcp-configs.sh

# Edit master MCP config (will auto-sync via git hook)
vim home/.config/mcp/mcp-master.json
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
# macOS: Install brew packages and run setup
cd ~/.dotfiles && zsh macOS/setup_macos.sh

# Arch Linux: Full setup
bash arch/setup_arch.sh
```

### Git Worktree Management

```bash
git wt list       # List worktrees
git mkwt <name>   # Create new worktree
git rmwt <name>   # Remove worktree
```

## Project Architecture

### Directory Structure

- **`home/`** - Main dotfiles directory (symlinked to home via Stow)
    - `.config/` - XDG-compliant config directory (zsh, nvim, git, tmux, mcp, etc.)
    - `.codex/` - OpenAI Codex CLI configuration
    - `.zshenv`, `.zprofile` - Zsh shell initialization
    - `Makefile` - Stow management automation
- **`macOS/`** - macOS-specific setup (Brewfile, setup script)
- **`arch/`** - Arch Linux-specific setup (setup script)
- **`scripts/`** - Utility scripts (MCP config sync, etc.)
- **`docs/ai-tools/`** - Detailed setup guides for AI tools
- **`.pre-commit-config.yaml`** - Pre-commit hook definitions
- **`.git/hooks/`** - Custom git hooks (auto-sync MCP on checkout/merge)

### Key Design Patterns

#### 1. Master MCP Configuration (Single Source of Truth)

The repository uses a **master MCP config** pattern:

- **Source**: `home/.config/mcp/mcp-master.json` - single, authoritative config
- **Targets**: Automatically synced to multiple AI tools
    - `~/.config/mcp/mcp_config.json` (Generic MCP format)
    - `~/.config/github-copilot/mcp.json` (GitHub Copilot CLI)
    - `~/.config/.copilot/mcp-config.json` (GitHub Copilot)
    - `~/.config/github-copilot/intellij/mcp.json` (IntelliJ)
    - `~/.config/.codex/` (OpenAI Codex)
- **Automation**: `scripts/sync-mcp-configs.sh` performs format transformation
- **Git Integration**: `post-checkout` and `post-merge` hooks auto-sync when `mcp-master.json` changes
- **MCP Servers**: filesystem, memory, sequential-thinking, railway, github, supabase

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
- **`.env`** (gitignored) - Sensitive environment variables sourced at runtime
- **Z4H Framework** - Zsh4humans for modern, fast zsh configuration

#### 4. Stow-Based File Management

Uses GNU Stow for dotfile symlink management:

- Single `home/` package contains all user dotfiles
- `Makefile` provides convenience targets (stow, restow, unstow, debug)
- `.stow-local-ignore` and `.stow-global-ignore` control what's symlinked
- Automatic backup of existing files before symlinking
- Dry-run mode available for previewing changes

#### 5. Environment Variable Management

Sensitive configuration is externalized:

- **Template**: `home/.config/zsh/.env.example` - documents all required variables
- **Runtime**: `home/.config/zsh/.env` - actual values, gitignored, sourced by `.zshrc`
- **Storage**: Real values kept in 1Password or password manager
- **Required vars**: SUPABASE_PROJECT_REF, GITHUB_TOKEN, BRAVE_API_KEY, OPENAI_API_KEY, AWS config

### Git Hooks Automation

- **`post-checkout`** - Runs `sync-mcp-configs.sh` if `mcp-master.json` changed
- **`post-merge`** - Runs `sync-mcp-configs.sh` if `mcp-master.json` changed
- Includes safety checks to prevent errors and verify stow is applied

### Pre-commit Checks

Configured in `.pre-commit-config.yaml`:

- YAML/JSON/TOML validation
- File size limits
- Case conflict detection
- Symlink verification
- Private key detection
- AWS credentials detection
- Python linting

### Tool Integrations

#### Neovim

- **Location**: `home/.config/nvim/`
- **Setup**: LazyVim (Lua-based, lazy loading)
- **Files**: `init.lua`, `lazyvim.json`, `lazy-lock.json`

#### Git

- **Location**: `home/.config/git/config`
- **Worktree Aliases**: Custom aliases for git worktree management

#### Tmux

- **Location**: `home/.config/tmux/tmux.conf`
- **Plugins**: TPM (Tmux Plugin Manager), tmux-resurrect (session persistence)
- **Features**: Extensive key bindings, status bar customization

#### Mise (Version Manager)

- **Location**: `home/.config/mise/`
- **Purpose**: Manages runtime versions (Node, Python, Go, etc.)

#### GitHub Copilot & MCP

- Integrated via master MCP config
- GitHub server for API access (requires GITHUB_TOKEN)
- Sequential thinking server for complex reasoning
- Filesystem access limited to specific directories

### macOS Setup

- **Brewfile**: Comprehensive list of packages, casks, fonts, and formulae
- **setup_macos.sh**: Automation script
    - Installs Homebrew if not present
    - Runs `brew bundle` to install packages
    - Applies stow for dotfiles
    - Runs additional setup scripts
- **Key tools installed**: zsh, git, tmux, neovim, ripgrep, fzf, jq, yq, bat, fd, zoxide, direnv, yazi, etc.

## Important Files

### Configuration

- `home/.config/zsh/.zshrc` - Main interactive shell config with aliases, completions, tool integrations
- `home/.config/mcp/mcp-master.json` - Master MCP server configuration (source of truth)
- `home/.config/git/config` - Git configuration with worktree management
- `home/.config/nvim/init.lua` - Neovim initialization

### Automation

- `scripts/sync-mcp-configs.sh` - Syncs master MCP config to all AI tools
- `.git/hooks/post-checkout` and `.git/hooks/post-merge` - Auto-sync triggers
- `home/Makefile` - Stow management targets

### Setup & Installation

- `macOS/Brewfile` - Homebrew packages, casks, and fonts
- `macOS/setup_macos.sh` - macOS setup automation
- `arch/setup_arch.sh` - Arch Linux setup automation

### Documentation

- `README.md` - Main repository documentation
- `docs/ai-tools/` - Setup guides for GitHub Copilot, IntelliJ, Claude/MCP, OpenAI Codex
- `docs/archive/` - Legacy documentation

## Workflow Notes

### Adding or Modifying MCP Servers

1. Edit `home/.config/mcp/mcp-master.json` (the master config)
2. Git hooks will automatically trigger `sync-mcp-configs.sh` on next git operation
3. Or manually run `~/.dotfiles/scripts/sync-mcp-configs.sh`
4. Verify the config is synced to all tool locations

### Installing New Tools

1. Add to `macOS/Brewfile` (if on macOS)
2. Run `brew bundle` from the repository root
3. Or manually run `brew install <package>`
4. Add any configuration to appropriate location in `home/.config/`
5. Test with `make debug` to see if symlinks would be created correctly
6. Run `make stow` to apply

### Branching Strategy for Development

- **Main branch**: `master` - stable dotfiles
- **Development branch**: `chezmoi` - exploring migration to Chezmoi with age encryption
- **Feature branches**: Create feature branches off `master` for new tool configs, improvements

### Development Container Support

- Dev container setup in `home/.config/dev-container/`
- Includes user/group mapping for container development
- Environment variable injection supported

## Pre-commit and Testing

- Run `pre-commit run --all-files` before committing
- Checks for YAML/JSON/TOML syntax, private keys, AWS credentials
- Prevents accidental secret commits
- All checks must pass before merge
