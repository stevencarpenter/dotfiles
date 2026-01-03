# My dotfiles

This directory contains the dotfiles for my systems which are macOS or Arch(by the way)

## Requirements

Ensure you have the following installed on your system

### Run Manually On Fresh OS Install for any Unix System
```shell
# Setup ssh key
ssh-keygen -t ed25519 -C "$USER macbook @ $EPOCHSECONDS"

# Create directories
mkdir -p ~/projects ~/programs
```

### Git and Stow
#### Arch
```
pacman -S git stow
```

#### macOS
```shell
# Install brew and all my brew formulae and casks
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update && brew upgrade

brew install git stow
```

### Clone this repo y La Playa
```shell
# Clone my dotfiles
git clone git@github.com:stevencarpenter/.dotfiles.git ~/
```

On a work machine, you can clone this repo to your home directory, but make sure to run the following so we are using the correct private key for my Github.
```shell
git config --local core.sshCommand   'ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes
```

## Stow plan command. Remove n for live run.

```shell
cd ~/.dotfiles
stow -nvvv home  # Plan mode
stow home        # Apply dotfiles
```

## MCP Configuration Sync

This repo uses **one master MCP config** that syncs to all AI tools automatically.

### Initial Setup

After stowing, sync MCP configs once:

```shell
~/.dotfiles/scripts/sync-mcp-configs.sh
```

### Auto-Sync on Git Operations

Git hooks automatically run the sync when `mcp-master.json` changes:

- ✅ `post-checkout` - After switching branches
- ✅ `post-merge` - After pulling changes

### Manual Updates

To add/modify MCP servers:

```shell
vim home/.config/mcp/mcp-master.json  # Edit master config
~/.dotfiles/scripts/sync-mcp-configs.sh  # Sync to all tools
```

This syncs to:

- `~/.config/.copilot/mcp-config.json` (GitHub Copilot)
- `~/.config/github-copilot/mcp.json` (GitHub Copilot CLI)
- `~/.config/github-copilot/intellij/mcp.json` (IntelliJ)
- `~/.config/mcp/mcp_config.json` (Claude/other tools)

## Environment Variables Setup

This repository uses environment variables for sensitive configuration. After cloning:

1. **Copy the template file:**
   ```shell
   cp ~/.config/zsh/.env.example ~/.config/zsh/.env
   ```

2. **Fill in your values** - Store sensitive tokens in 1Password and populate `.env` with:
   - `SUPABASE_PROJECT_REF` - Your Supabase project reference
   - `GITHUB_TOKEN` - GitHub Personal Access Token (for MCP, Copilot)
   - `BRAVE_API_KEY` - Brave Search API key
   - `OPENAI_API_KEY` - OpenAI API key (if using Codex CLI)
   - See `.env.example` for complete list

3. **Secure the file:**
   ```shell
   chmod 600 ~/.config/zsh/.env
   ```

**Note:** The `.env` file is already gitignored and will never be committed to the repository.

## AI Tools Configuration
Comprehensive setup and configuration for AI-powered development tools:

- **[MCP (Model Context Protocol)](docs/ai-tools/mcp-setup.md)** - Configure AI assistants with secure access to local and remote resources
- **[IntelliJ IDEA Copilot](docs/ai-tools/intellij-copilot-setup.md)** - Complete GitHub Copilot setup for IntelliJ IDEA
- **[Copilot CLI](docs/ai-tools/copilot-cli-setup.md)** - Terminal integration for GitHub Copilot
- **[OpenAI Codex CLI](docs/ai-tools/openai-codex-cli-setup.md)** - Command-line access to OpenAI's code generation
- **[Custom Terraform Instructions](docs/ai-tools/terraform-instructions.md)** - Best practices for AI-generated Terraform code

See the [AI Tools documentation](docs/ai-tools/) for detailed setup guides.
