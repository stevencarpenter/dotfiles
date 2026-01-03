# GitHub Copilot CLI Setup Guide

## Overview

GitHub Copilot CLI brings AI-powered assistance directly to your terminal, helping you find the right commands, explain shell syntax, and generate scripts. This guide covers installation, configuration, and usage.

## Prerequisites

- Active GitHub Copilot subscription
- Node.js 18+ (for npm installation)
- GitHub CLI (`gh`) installed
- Shell: Zsh, Bash, or Fish

## Installation

### Method 1: GitHub CLI Extension (Recommended)

```bash
# Install as GitHub CLI extension
gh extension install github/gh-copilot

# Verify installation
gh copilot --version
```

### Method 2: NPM Global Install

```bash
# Install via npm
npm install -g @githubnext/github-copilot-cli

# Verify installation
github-copilot-cli --version
```

### Method 3: Homebrew (macOS/Linux)

```bash
# Add tap
brew tap github/gh

# Install
brew install github-copilot-cli

# Verify
gh copilot --version
```

## Authentication

### Authenticate with GitHub

```bash
# If using gh extension
gh auth login

# Follow the prompts:
# 1. Select GitHub.com
# 2. Select HTTPS or SSH
# 3. Authenticate in browser

# Enable Copilot
gh copilot config
```

### Verify Access

```bash
# Check authentication status
gh auth status

# Test Copilot access
gh copilot suggest "list files"
```

## Shell Integration

### Zsh Setup (Recommended for this dotfiles repo)

Add to your `~/.config/zsh/.zshrc`:

```bash
# GitHub Copilot CLI
eval "$(gh copilot alias -- zsh)"
```

**Or use the convenience aliases:**

```bash
# Add these aliases to ~/.config/zsh/.zshrc
alias '??'='gh copilot suggest -t shell'
alias 'git?'='gh copilot suggest -t git'
alias 'gh?'='gh copilot suggest -t gh'
```

**Reload shell:**
```bash
source ~/.config/zsh/.zshrc
```

### Bash Setup

Add to `~/.bashrc`:

```bash
# GitHub Copilot CLI
eval "$(gh copilot alias -- bash)"
```

### Fish Setup

Add to `~/.config/fish/config.fish`:

```fish
# GitHub Copilot CLI
gh copilot alias -- fish | source
```

## Usage

### 1. Suggest Shell Commands

**Using alias:**
```bash
# General command suggestions
?? "find large files"

# Example output:
# find . -type f -size +100M
```

**Using full command:**
```bash
gh copilot suggest -t shell "compress all log files"

# Copilot suggests:
# tar -czf logs.tar.gz *.log
```

**Interactive mode:**
```bash
# Start interactive session
??

# Then type your query
# Copilot provides multiple suggestions
# Use arrow keys to select
# Press Enter to execute or copy
```

### 2. Git Command Suggestions

```bash
# Git-specific suggestions
git? "undo last commit but keep changes"

# Copilot suggests:
# git reset --soft HEAD~1
```

**Common git queries:**
```bash
git? "squash last 3 commits"
git? "create branch from specific commit"
git? "show files changed in commit"
git? "revert specific file to previous version"
```

### 3. GitHub CLI Suggestions

```bash
# GitHub CLI specific
gh? "list open pull requests"

# Copilot suggests:
# gh pr list --state open
```

**Common gh queries:**
```bash
gh? "create pull request"
gh? "view repository issues"
gh? "merge pull request"
gh? "create new repository"
```

### 4. Explain Shell Commands

**Explain complex commands:**
```bash
gh copilot explain "find . -name '*.log' -mtime +30 -delete"

# Copilot explains each part:
# - find . : search current directory
# - -name '*.log' : match files ending in .log
# - -mtime +30 : modified more than 30 days ago
# - -delete : delete matched files
```

**With alias:**
```bash
# Add explain alias to ~/.config/zsh/.zshrc
alias 'explain'='gh copilot explain'

# Use it:
explain "awk '{print $2}' file.txt | sort | uniq -c"
```

## Advanced Configuration

### Custom Aliases

Add to `~/.config/zsh/.zshrc`:

```bash
# Quick Copilot access
alias cop='gh copilot suggest -t shell'
alias gcop='gh copilot suggest -t git'
alias hcop='gh copilot explain'

# Terraform-specific
alias tfcop='gh copilot suggest -t shell "terraform"'

# Docker-specific
alias dcop='gh copilot suggest -t shell "docker"'

# Kubernetes-specific
alias kcop='gh copilot suggest -t shell "kubectl"'
```

### Environment Variables

```bash
# Add to ~/.zshenv
export GITHUB_COPILOT_CLI_MODEL="gpt-4"  # Use GPT-4 for better suggestions
export GITHUB_COPILOT_CLI_EDITOR="nvim"  # Default editor for copying
```

### Configuration File

Create `~/.config/gh-copilot/config.yml`:

```yaml
# Copilot CLI Configuration
model: gpt-4
editor: nvim
shell: zsh
auto_execute: false  # Always prompt before executing
explain_by_default: true  # Show explanations with suggestions
```

## Common Use Cases

### 1. System Administration

```bash
# Find and fix permissions
?? "find all files with wrong permissions and fix"

# Monitor system resources
?? "show top 10 processes by memory usage"

# Manage services
?? "restart nginx service"
```

### 2. File Operations

```bash
# Bulk operations
?? "rename all .txt files to .md"

# Find and replace
?? "replace text in all files in directory"

# Backup and compression
?? "create encrypted backup of home directory"
```

### 3. Git Workflows

```bash
# Complex git operations
git? "interactive rebase last 5 commits"
git? "cherry-pick commit to another branch"
git? "find who deleted a file"
```

### 4. Terraform Operations

```bash
# Terraform commands
?? "terraform plan with specific var file"
?? "find all terraform state files"
?? "format all terraform files recursively"
```

### 5. Docker & Kubernetes

```bash
# Docker
?? "remove all stopped containers"
?? "build and tag docker image"

# Kubernetes
?? "get pods in failed state"
?? "scale deployment to 5 replicas"
```

### 6. Text Processing

```bash
# AWK, sed, grep
?? "extract second column from CSV"
?? "replace text between patterns"
?? "count unique values in log file"
```

## Keyboard Shortcuts

### In Interactive Mode

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate suggestions |
| `Enter` | Execute selected command |
| `Tab` | Copy to clipboard |
| `e` | Explain selected command |
| `r` | Revise query |
| `q` | Quit |
| `Ctrl+C` | Cancel |

### Shell Integration

Add to `~/.config/zsh/.zshrc`:

```bash
# Ctrl+G to trigger Copilot
bindkey -s '^G' '??^M'

# Ctrl+H for git help
bindkey -s '^H' 'git?^M'
```

## Best Practices

### 1. Be Specific

**Good:**
```bash
?? "find all .log files larger than 100MB modified in last week"
```

**Too vague:**
```bash
?? "find logs"
```

### 2. Use Context

```bash
# Include relevant context
?? "using awk, extract IP addresses from nginx access log"
```

### 3. Verify Before Executing

- Always review suggested commands
- Use `explain` for complex commands
- Test destructive operations in safe environment

### 4. Learn From Suggestions

- Study the suggested commands
- Use `explain` to understand each part
- Build your knowledge over time

### 5. Iterate Queries

```bash
# Start broad
?? "backup files"

# Refine based on suggestion
?? "create incremental backup with rsync"
```

## Integration with Dotfiles

### Shell Configuration

Add to `~/.config/zsh/.zshrc`:

```bash
# ============================================
# GitHub Copilot CLI Configuration
# ============================================

# Load Copilot aliases
eval "$(gh copilot alias -- zsh)"

# Custom shortcuts
alias '??'='gh copilot suggest -t shell'
alias 'git?'='gh copilot suggest -t git'
alias 'gh?'='gh copilot suggest -t gh'
alias 'explain'='gh copilot explain'

# Quick access for common tools
alias 'tf?'='gh copilot suggest -t shell "terraform"'
alias 'k?'='gh copilot suggest -t shell "kubectl"'
alias 'd?'='gh copilot suggest -t shell "docker"'

# Keyboard shortcuts
bindkey -s '^G' '??^M'  # Ctrl+G for Copilot
```

### Tmux Integration

Add to `~/.config/tmux/tmux.conf`:

```tmux
# Copilot in tmux popup
bind-key C-g display-popup -E "gh copilot suggest -t shell"
bind-key C-h display-popup -E "gh copilot suggest -t git"
```

## Troubleshooting

### Command Not Found

```bash
# Verify installation
which gh
gh --version

# Reinstall extension
gh extension remove copilot
gh extension install github/gh-copilot
```

### Authentication Errors

```bash
# Check auth status
gh auth status

# Re-authenticate
gh auth login

# Refresh token
gh auth refresh -s copilot
```

### Copilot Not Responding

```bash
# Check GitHub status
gh copilot status

# View logs
gh copilot logs

# Clear cache
rm -rf ~/.config/gh/copilot/cache
```

### Network/Proxy Issues

```bash
# Configure proxy
export HTTPS_PROXY="http://proxy.example.com:8080"

# Or in gh config
gh config set http_proxy "http://proxy.example.com:8080"
```

### Shell Integration Not Working

```bash
# Reload shell config
source ~/.config/zsh/.zshrc

# Check if aliases are loaded
alias | grep copilot

# Verify gh is in PATH
echo $PATH | grep -o "[^:]*gh[^:]*"
```

## Performance Tips

### 1. Caching

Copilot CLI caches responses:

```bash
# View cache location
ls ~/.config/gh/copilot/cache/

# Clear old cache
find ~/.config/gh/copilot/cache/ -mtime +7 -delete
```

### 2. Network Optimization

```bash
# Use faster DNS
export GH_COPILOT_DNS="8.8.8.8"
```

### 3. Reduce Latency

```bash
# Keep session alive
gh copilot warm-up

# Background refresh
gh copilot refresh &
```

## Updates

### Update Extension

```bash
# Update gh CLI
brew upgrade gh  # macOS
# or
gh upgrade  # if installed via gh

# Update Copilot extension
gh extension upgrade copilot

# Verify version
gh copilot version
```

### Auto-Update Script

Create `~/scripts/update-copilot.sh`:

```bash
#!/bin/bash
# Update GitHub Copilot CLI

echo "Updating GitHub CLI..."
brew upgrade gh 2>/dev/null || gh upgrade

echo "Updating Copilot extension..."
gh extension upgrade copilot

echo "✓ Updates complete"
gh copilot version
```

Make executable:
```bash
chmod +x ~/scripts/update-copilot.sh
```

## Additional Resources

- [GitHub Copilot CLI Docs](https://docs.github.com/en/copilot/github-copilot-in-the-cli)
- [GitHub CLI Manual](https://cli.github.com/manual/)
- [Shell Integration Examples](https://github.com/github/gh-copilot/tree/main/examples)
- [Community Tips](https://github.com/github/gh-copilot/discussions)

## See Also

- [IntelliJ IDEA Copilot Setup](./intellij-copilot-setup.md)
- [OpenAI Codex CLI Setup](./openai-codex-cli-setup.md)
- [Terraform Instructions](./terraform-instructions.md)
