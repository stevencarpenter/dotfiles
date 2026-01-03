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
chezmoi edit ~/.zshrc

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
~/.local/share/chezmoi/scripts/sync-mcp-configs.sh
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

## Environment Variables Setup

This repository uses encrypted environment variables. They are automatically decrypted when you run `chezmoi apply`.

If you need to update environment variables:

1. **Edit the encrypted file:**
   ```shell
   chezmoi edit ~/.config/zsh/.env
   ```

2. **Or re-add with encryption:**
   ```shell
   # Edit the file directly, then
   chezmoi add --encrypt ~/.config/zsh/.env
   ```

**Required variables** (documented in `.env.example`):
- `SUPABASE_PROJECT_REF` - Your Supabase project reference
- `GITHUB_TOKEN` - GitHub Personal Access Token (for MCP, Copilot)
- `BRAVE_API_KEY` - Brave Search API key
- `OPENAI_API_KEY` - OpenAI API key (if using Codex CLI)

## AI Tools Configuration

Comprehensive setup and configuration for AI-powered development tools:

- **[MCP (Model Context Protocol)](docs/ai-tools/mcp-setup.md)** - Configure AI assistants with secure access to local and remote resources
- **[IntelliJ IDEA Copilot](docs/ai-tools/intellij-copilot-setup.md)** - Complete GitHub Copilot setup for IntelliJ IDEA
- **[Copilot CLI](docs/ai-tools/copilot-cli-setup.md)** - Terminal integration for GitHub Copilot
- **[OpenAI Codex CLI](docs/ai-tools/openai-codex-cli-setup.md)** - Command-line access to OpenAI's code generation
- **[Custom Terraform Instructions](docs/ai-tools/terraform-instructions.md)** - Best practices for AI-generated Terraform code

See the [AI Tools documentation](docs/ai-tools/) for detailed setup guides.

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
