# Migration Plan: Stow to Chezmoi with Age Encryption

> **Status:** ✅ **COMPLETED** - This migration has been completed. This document is archived for historical reference.

> **Confidence Indicators:**
> - 🟢 **High Confidence:** Standard practices, verified against directory tree.
> - 🟡 **Verification Needed:** Depends on specific file contents or workflows that may vary.

## Project Overview

**Goal:** Migrate `~/.dotfiles` (Stow) to `~/.local/share/chezmoi` (Chezmoi).
**Strategy:** "Copy-heavy" migration to ensure stability. Encrypt secrets using `age`. Distinguish Work vs. Personal contexts.

---

## Phase 1: Initialization & Secrets 🟢

### 1.1 Install Tools

```shell
brew install chezmoi age
```

### 1.2 Generate Encryption Identity

*We will generate an age key and back it up to 1Password immediately.*

1. **Generate Key:**
   ```shell
   mkdir -p ~/.config/chezmoi
   age-keygen -o ~/.config/chezmoi/key.txt
   chmod 600 ~/.config/chezmoi/key.txt
   ```
2. **Backup to 1Password:**
    * Create a **Secure Note** in 1Password named `dotfiles-age-key`.
    * Paste the full contents of `~/.config/chezmoi/key.txt`.
    * *Note: On a new machine, you will manually create this file from the note before applying.*

### 1.3 Configure Chezmoi

Run `chezmoi init`. Create `~/.local/share/chezmoi/.chezmoi.toml.tmpl`:

```toml
{{ - $machine : = promptStringOnce . "machine" "Machine type (work-mac/personal-mac)" - } }

encryption = "age"

[age]
identity = "~/.config/chezmoi/key.txt"
recipient = "age1..." # 🟡 ACTION: Replace with public key from key.txt

[data]
machine = { { $machine | quote } }

{ { - if eq $machine "work-mac" } }
email = "steve@company.com" # 🟡 ACTION: Replace
{ { - else } }
email = "steve@personal.com" # 🟡 ACTION: Replace
{ { - end } }
```

---

## Phase 2: Static Config Migration 🟢

*We will copy these directories "as is".*

### 2.1 Core Configs

Execute in terminal:

```shell
# Prepare destination
mkdir -p ~/.local/share/chezmoi/dot_config/{zsh,nvim,tmux,ghostty,mise,dev-container,git}

# Zsh (Copying specific files to avoid clutter)
cp ~/.dotfiles/home/.zshenv ~/.local/share/chezmoi/dot_zshenv
cp ~/.dotfiles/home/.config/zsh/.zshrc ~/.local/share/chezmoi/dot_config/zsh/dot_zshrc
cp ~/.dotfiles/home/.config/zsh/.zshenv ~/.local/share/chezmoi/dot_config/zsh/dot_zshenv
cp ~/.dotfiles/home/.config/zsh/.zprofile ~/.local/share/chezmoi/dot_config/zsh/dot_zprofile
cp ~/.dotfiles/home/.config/zsh/.p10k.zsh ~/.local/share/chezmoi/dot_config/zsh/dot_p10k.zsh

# Global Ignore
cp ~/.dotfiles/home/.gitignore_global ~/.local/share/chezmoi/dot_gitignore_global

# App Configs
cp -R ~/.dotfiles/home/.config/nvim/ ~/.local/share/chezmoi/dot_config/nvim/
cp -R ~/.dotfiles/home/.config/tmux/ ~/.local/share/chezmoi/dot_config/tmux/
cp ~/.dotfiles/home/.config/ghostty/config ~/.local/share/chezmoi/dot_config/ghostty/config
cp ~/.dotfiles/home/.config/mise/config.toml ~/.local/share/chezmoi/dot_config/mise/config.toml
cp -R ~/.dotfiles/home/.config/dev-container/ ~/.local/share/chezmoi/dot_config/dev-container/

# Docs (Unmanaged - place outside chezmoi management)
cp -R ~/.dotfiles/docs ~/.local/share/chezmoi/
```

### 2.2 Fix Dotfiles inside Copied Directories

*Chezmoi ignores dotfiles inside source dirs unless renamed.*

```shell
# Neovim
mv ~/.local/share/chezmoi/dot_config/nvim/.gitignore ~/.local/share/chezmoi/dot_config/nvim/dot_gitignore
mv ~/.local/share/chezmoi/dot_config/nvim/.neoconf.json ~/.local/share/chezmoi/dot_config/nvim/dot_neoconf.json

# Tmux
mv ~/.local/share/chezmoi/dot_config/tmux/.gitignore ~/.local/share/chezmoi/dot_config/tmux/dot_gitignore
```

---

## Phase 3: Templating & Secrets

### 3.1 Git Config (Templated) 🟢

Create `~/.local/share/chezmoi/dot_config/git/config.tmpl`.
*Content:*

```gitconfig
[user]
    name = Steven Carpenter
    email = {{ .email }}

[core]
    excludesfile = ~/.gitignore_global
    editor = nvim

# 🟡 ACTION: Copy remaining static content from ~/.dotfiles/home/.config/git/config
```

### 3.2 Zsh Environment (Encrypted) 🟡

*We assume you will paste your 1Password Secure Note contents here.*
Create `~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env.tmpl`.

*Content Structure:*

```shell
# Encrypted Environment Variables

{{- if eq .machine "work-mac" }}
# 🟡 ACTION: Paste Work-specific env vars here
export WORK_TOKEN="..."
{{- else }}
# 🟡 ACTION: Paste Personal-specific env vars here
export PERSONAL_TOKEN="..."
{{- end }}

# 🟡 ACTION: Paste Shared env vars here
export OPENAI_API_KEY="..."
```

*Run:* `chezmoi encrypt ~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env.tmpl` (if using VS Code plugin) OR `chezmoi add --encrypt` after creating the
file in place.

### 3.3 Codex Config (Encrypted) 🟢

```shell
chezmoi add --encrypt ~/.codex/config.toml
```

### 3.4 MCP Configs (Deduplication Strategy) 🟡

*The current dotfiles use `scripts/sync-mcp-configs.sh` to transform `mcp-master.json` into different formats. For chezmoi, we have two options:*

**Option A: Script-based (recommended for now)**
Keep the sync script and run it as a chezmoi script:

1. **Copy master config:**
   ```shell
   mkdir -p ~/.local/share/chezmoi/private_dot_config/mcp
   cp ~/.dotfiles/home/.config/mcp/mcp-master.json ~/.local/share/chezmoi/private_dot_config/mcp/mcp-master.json
   ```

2. **Create run script:**
   Create `~/.local/share/chezmoi/.chezmoiscripts/run_after_sync-mcp.sh`:
   ```shell
   #!/usr/bin/env bash
   # Run the MCP sync script after apply
   ~/.local/share/chezmoi/scripts/sync-mcp-configs.sh
   ```

3. **Copy sync script:**
   ```shell
   mkdir -p ~/.local/share/chezmoi/scripts
   cp ~/.dotfiles/scripts/sync-mcp-configs.sh ~/.local/share/chezmoi/scripts/
   ```

**Option B: Template-based (future enhancement)**
Create a chezmoi template that generates all 4 config formats. This requires more upfront work but eliminates the external script dependency.

1. **Create Source Template:**
   Create `~/.local/share/chezmoi/private_dot_config/mcp/mcp-master.json.tmpl`.
   *Use `{{ if eq .machine ... }}` logic for token differences.*

2. **Create derived templates** at:
    - `dot_config/github-copilot/mcp.json.tmpl` (servers format)
    - `dot_config/github-copilot/intellij/mcp.json.tmpl` (servers format)
    - `dot_config/private_dot_copilot/mcp-config.json.tmpl` (mcpServers format with tools array)
    - `dot_config/mcp/mcp_config.json.tmpl` (mcpServers format with schema)

### 3.5 GitHub Copilot Instructions 🟢

*Copy Copilot instruction files:*

```shell
mkdir -p ~/.local/share/chezmoi/dot_config/github-copilot/intellij

# VS Code / General Copilot
cp ~/.dotfiles/home/.config/github-copilot/copilot-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/
cp ~/.dotfiles/home/.config/github-copilot/global-copilot-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/
cp ~/.dotfiles/home/.config/github-copilot/global-git-commit-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/

# IntelliJ-specific
cp ~/.dotfiles/home/.config/github-copilot/intellij/copilot-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/intellij/
cp ~/.dotfiles/home/.config/github-copilot/intellij/global-copilot-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/intellij/
cp ~/.dotfiles/home/.config/github-copilot/intellij/global-git-commit-instructions.md ~/.local/share/chezmoi/dot_config/github-copilot/intellij/
```

---

## Phase 4: System Automation 🟢

### 4.1 Brewfile

Create `~/.local/share/chezmoi/.chezmoiscripts/darwin/run_onchange_brew-bundle.sh.tmpl`.

```shell
#!/usr/bin/env bash
# Brewfile hash: {{ include "dot_Brewfile" | sha256sum }}
set -euo pipefail
brew bundle --file="{{ .chezmoi.sourceDir }}/dot_Brewfile" --no-lock
```

*Copy file:*

```shell
cp ~/.dotfiles/macOS/Brewfile ~/.local/share/chezmoi/dot_Brewfile
```

### 4.2 macOS Defaults

Create `~/.local/share/chezmoi/.chezmoiscripts/darwin/run_once_setup-macos.sh`.
*Action:* Copy contents from `~/.dotfiles/macOS/setup_macos.sh`.

---

## Phase 5: Verification & Swap 🟢

### 5.1 Verify

1. Run `chezmoi diff`.
    * *Expectation:* No major diffs for static files. Git config and .env should show replacement logic.
2. Run `chezmoi apply --dry-run --verbose`.

### 5.2 Commit

```shell
cd ~/.local/share/chezmoi
git init
git add .
git commit -m "feat: Initial migration to chezmoi"
# 🟡 ACTION: Add your new GitHub remote
# git remote add origin ...
```

### 5.3 Swap

1. **Unlink Stow:**
   ```shell
   cd ~/.dotfiles
   stow -D home
   ```
2. **Apply Chezmoi:**
   ```shell
   chezmoi apply
   ```
3. **Validate:** Check if `nvim`, `git`, and `zsh` still load correctly.

---

## Summary Checklist for Agent Prompting

- [ ] Installed `chezmoi` & `age`.
- [ ] Created `key.txt` and saved to 1Password.
- [ ] Created `.chezmoi.toml.tmpl` with Work/Personal logic.
- [ ] Migrated static config folders (`nvim`, `tmux`, etc.).
- [ ] Templated `git/config`.
- [ ] Created encrypted `zsh/dot_env` from 1Password notes.
- [ ] Set up MCP configs (script-based or template-based).
- [ ] Copied GitHub Copilot instruction files.
- [ ] Set up `run_onchange` Brewfile script.
- [ ] Verified diffs and performed swap.
