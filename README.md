# Dotfiles

This directory contains the dotfiles for my systems (macOS or Arch Linux), managed with **Chezmoi** and **age encryption**.

## Requirements

Ensure you have the following installed on your system:

### Run Manually On Fresh OS Install for any Unix System

```shell
# Setup ssh key
ssh-keygen -t ed25519 -C "$USER macbook @ $EPOCHSECONDS"

# Create directories
mkdir -p ~/projects ~/programs
```

### Install Chezmoi and Age

#### Arch Linux

```bash
pacman -S chezmoi age
```

#### macOS

```shell
# Install Homebrew (if not present)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update && brew upgrade

# Install chezmoi and age
brew install chezmoi age
```

### Setup Age Encryption Key

Before initializing chezmoi, you need to set up your age encryption key from 1Password:

```shell
# Create chezmoi config directory
mkdir -p ~/.config/chezmoi

# Create the age key file from your 1Password backup
# (copy the contents of your "dotfiles-age-key" secure note)
cat > ~/.config/chezmoi/key.txt << 'EOF'
# created: <timestamp>
# public key: age1462h0ed4ufkjrq0wu326l30c8hay9uewlsaudk89mgqjc5540vrqacejsz
AGE-SECRET-KEY-<your-secret-key>
EOF

# Secure the key file
chmod 600 ~/.config/chezmoi/key.txt
```

### Clone and Initialize

```shell
# Initialize chezmoi with this repo
chezmoi init git@github.com:stevencarpenter/dotfiles.git

# Preview what will be applied
chezmoi diff

# Apply dotfiles
chezmoi apply
```

On a work machine, configure git to use the correct SSH key:

```shell
cd ~/.local/share/chezmoi
git config --local core.sshCommand 'ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes'
```

## Common Chezmoi Commands

```shell
# Preview changes before applying
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

# Update from remote repository
chezmoi update

# View managed files
chezmoi managed
```

## MCP Configuration Sync

This repo uses **one master MCP config** that syncs to all AI tools automatically.

### Automatic Sync

MCP configs are synced automatically after `chezmoi apply` via the `run_after_sync-mcp.sh` script.

### Manual Sync (if needed)

```shell
uv run sync-mcp-configs
```

The helper is also available as a standalone uv script for compatibility with the `run_after_sync-mcp.sh`
helper in `.chezmoiscripts`:

```shell
uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs
```

### Editing MCP Config

```shell
chezmoi edit ~/.config/mcp/mcp-master.json
chezmoi apply  # Sync runs automatically
```

This syncs to:

- `~/.config/.copilot/mcp-config.json` (GitHub Copilot)
- `~/.config/github-copilot/mcp.json` (GitHub Copilot CLI)
- `~/.config/github-copilot/intellij/mcp.json` (IntelliJ)
- `~/.config/mcp/mcp_config.json` (Claude/other tools)

### Linting and Testing

Use the uv-first tooling that ships with this project:

```shell
uv run ruff check scripts tests
uv run pytest tests/ -v
```

If you need to run a specific suite or module, add arguments after `pytest` (e.g., `uv run pytest tests/test_sync_mcp_configs.py -v`).

## Environment Variables Setup

This repository uses age-encrypted environment variables. The encrypted file is stored in the repo as `dot_config/zsh/encrypted_dot_env` and automatically decrypted to `~/.config/zsh/.env` when you run `chezmoi apply`.

### How Chezmoi Encryption Works

Chezmoi uses the `encrypted_` filename prefix to identify files that need decryption on apply:
- **Source**: `dot_config/zsh/encrypted_dot_env` (encrypted, safe to commit)
- **Target**: `~/.config/zsh/.env` (decrypted, never committed)

The `suffix = ""` setting in `~/.config/chezmoi/chezmoi.toml` prevents chezmoi from adding a redundant `.age` extension.

### Updating Environment Variables

1. **Edit the decrypted target file:**
   ```shell
   nvim ~/.config/zsh/.env
   ```

2. **Re-encrypt and update the source:**
   ```shell
   chezmoi add --encrypt ~/.config/zsh/.env
   ```

3. **Verify the source is encrypted before committing:**
   ```shell
   head -3 ~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env
   # Should show: -----BEGIN AGE ENCRYPTED FILE-----
   ```

### Required Variables

- `GITHUB_TOKEN` - GitHub Personal Access Token (for MCP, Copilot)
- `OPENAI_API_KEY` - OpenAI API key
- `SUPABASE_PROJECT_REF` - Supabase project reference (for MCP)
- `BRAVE_API_KEY` - Brave Search API key
- `CONTEXT7_API_KEY` - Context7 API key
- `NPM_TOKEN` - NPM authentication token
- `OPENROUTER_TOKEN` - OpenRouter API key
- `ATLASSIAN_API_TOKEN` - Atlassian/Jira API token (work)

## AI Tools Configuration

Comprehensive setup and configuration for AI-powered development tools:

- **[MCP (Model Context Protocol)](docs/ai-tools/mcp-setup.md)** - Configure AI assistants with secure access to local and remote resources
- **[IntelliJ IDEA Copilot](docs/ai-tools/intellij-copilot-setup.md)** - Complete GitHub Copilot setup for IntelliJ IDEA
- **[Copilot CLI](docs/ai-tools/copilot-cli-setup.md)** - Terminal integration for GitHub Copilot
- **[OpenAI Codex CLI](docs/ai-tools/openai-codex-cli-setup.md)** - Command-line access to OpenAI's code generation
- **[Ralph + OpenCode](docs/ai-tools/ralph-opencode-setup.md)** - Autonomous coding agent with LM Studio support
- **[Custom Terraform Instructions](docs/ai-tools/terraform-instructions.md)** – Best practices for AI-generated Terraform code

See the [AI Tools documentation](docs/ai-tools/) for detailed setup guides.

### Ralph + OpenCode Quick Start

After `chezmoi apply`, the `ralph-opencode` command is available globally:

```shell
# Check system health
ralph-opencode doctor

# Run a single iteration
ralph-opencode --prd ./prd.json

# Run overnight with safe mode
ralph-opencode --prd ./prd.json --until-complete --safe --max-hours 8

# Use with LM Studio (default)
ralph-opencode --model qwen2.5-coder-32b-instruct --prd ./prd.json

# Use with OpenRouter cloud models
ralph-opencode --base-url https://openrouter.ai/api/v1 \
    --model anthropic/claude-sonnet-4 --prd ./prd.json
```

## New Machine Quick Start

```shell
# 1. Install chezmoi and age
brew install chezmoi age  # macOS
# or: pacman -S chezmoi age  # Arch

# 2. Set up age key from 1Password (see instructions above)

# 3. Initialize and apply
chezmoi init git@github.com:stevencarpenter/dotfiles.git
chezmoi apply

# 4. Restart your shell
exec zsh
```
