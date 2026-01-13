# Ralph + OpenCode + LM Studio Cheat Sheet

Quick reference for working with the local AI agent loop stack integrated into chezmoi dotfiles.

---

## 🚀 Quick Start

### Installation
```bash
chezmoi apply
```

### Verify Setup
```bash
ralph-opencode doctor
```

### Single Iteration
```bash
ralph-opencode --prd ./prd.json
```

### Overnight Run
```bash
ralph-opencode --repo . --prd ./prd.json --until-complete --safe --max-hours 8
```

---

## 📋 Chezmoi Naming Conventions

Understanding how files are managed in the dotfiles repo:

| Convention | Source Path | Installed Path | Notes |
|-----------|------------|----------------|-------|
| `dot_` prefix | `dot_config/` | `~/.config/` | Converts dot to directory name |
| `dot_local/` | `dot_local/bin/` | `~/.local/bin/` | XDG data home |
| `executable_` prefix | `executable_script` | `script` (0755) | Sets executable bit |
| `.tmpl` suffix | `config.json.tmpl` | `config.json` | Chezmoi template (optional vars) |
| `encrypted_` prefix | `encrypted_secrets` | `secrets` | Age-encrypted file |
| `private_` prefix | `private_key` | `.key` (0600) | Private file permissions |

### Examples
```
dot_config/ralph/ralph.json.tmpl
  ↓ chezmoi apply
~/.config/ralph/ralph.json

dot_local/bin/executable_ralph-opencode
  ↓ chezmoi apply
~/.local/bin/ralph-opencode (executable)

dot_config/zsh/encrypted_dot_env
  ↓ chezmoi apply (decrypts)
~/.config/zsh/.env (0600)
```

---

## 🛠️ Ralph + OpenCode Stack

### File Locations

**Global Configuration:**
```
~/.config/ralph/ralph.json              # Ralph config (generated from template)
~/.config/opencode/opencode.json        # OpenCode config (generated from template)
~/.config/opencode/rules.toml           # Safe mode rules
~/.config/ralph/secrets.env             # Encrypted secrets (optional)
```

**Project Configuration (NEW):**
```
<repo-root>/ralph.json                  # Project Ralph config (overrides global)
<repo-root>/opencode.json               # Project OpenCode config (overrides global)
<repo-root>/rules.toml                  # Project safe mode rules
<repo-root>/.instructions.md            # Agent guidelines (passed to OpenCode)
<repo-root>/AGENTS.md                   # Alternative guidelines location
<repo-root>/CLAUDE.md                   # Alternative guidelines location
<repo-root>/prds/                       # Project PRD directory
<repo-root>/.opencode/agents/           # Project agent definitions
```

**Global Wrapper:**
```
~/.local/bin/ralph-opencode             # CLI wrapper (executable)
```

**State & Logs:**
```
~/.local/state/ralph/
├── logs/                               # Iteration logs by repo hash
├── metrics/                            # Performance metrics
└── runs/                               # Per-repo state
```

**Source in Chezmoi:**
```
~/.local/share/chezmoi/
├── dot_config/
│   ├── ralph/
│   │   ├── ralph.json.tmpl             # Global config template
│   │   └── secrets.env.example         # Secrets template
│   └── opencode/
│       ├── opencode.json.tmpl          # OpenCode config template
│       └── rules.toml                  # Safe mode rules
└── dot_local/bin/
    └── executable_ralph-opencode       # CLI wrapper script (996 lines)
```

---

## 🏗️ Project-Level Configuration (New!)

Projects can now store their own Ralph and OpenCode configurations, instructions, and PRDs. This enables:

- **Per-repo agent tuning**: Different models/settings per project
- **Project guidelines**: Captured in version control
- **Isolated PRDs**: Multiple feature PRDs per repo
- **Agent instructions**: Project-specific agent role and constraints

### Project File Structure

```
your-project/
├── ralph.json                      # Project Ralph config (optional)
├── opencode.json                   # Project OpenCode config (optional)
├── .instructions.md                # Agent guidelines (recommended)
├── rules.toml                      # Safe mode overrides (optional)
├── prds/                           # PRD storage directory
│   ├── prd-feature-a.json
│   ├── prd-feature-b.json
│   └── prd-bugfix.json
└── .opencode/
    └── agents/
        └── default.md              # Agent role definition
```

### Configuration Precedence (Updated)

```
1. CLI Flags                       (--model, --base-url, --prd, etc.)
   ↓
2. Environment Variables           (RALPH_MODEL, RALPH_BASE_URL, etc.)
   ↓
3. Project Config                  (./ralph.json in repo root)
   ↓
4. Global Config                   (~/.config/ralph/ralph.json)
   ↓
5. Built-in Defaults
```

**Project config overrides global config** for these fields:
- `opencode.model`
- `opencode.baseUrl`
- `opencode.apiKey` (sourced from env, not committed)
- `loop.*` settings
- `safeMode.*` settings
- `secretsFile`

### Project ralph.json

Minimal example:
```json
{
  "opencode": {
    "model": "deepseek-coder-v2",
    "baseUrl": "http://localhost:1234/v1",
    "tools": ["filesystem", "shell", "git"]
  },
  "loop": {
    "maxIterations": 50,
    "maxConsecutiveFailures": 5
  },
  "safeMode": {
    "enabled": false
  }
}
```

**All fields optional** — global defaults apply if not specified.

### Project opencode.json

Reference local OpenCode config:
```json
{
  "providers": [
    {
      "name": "lmstudio",
      "baseUrl": "http://127.0.0.1:1234/v1",
      "model": "deepseek-coder-v2",
      "maxTokens": 8000
    }
  ],
  "tools": [
    { "name": "filesystem", "enabled": true },
    { "name": "shell", "enabled": true },
    { "name": "git", "enabled": true }
  ]
}
```

### Project .instructions.md

Agent guidelines passed to OpenCode each iteration:
```markdown
# MyProject Agent Guidelines

## What You're Building
Implement features described in the PRD with high quality and test coverage.

## Code Style
- Use TypeScript strict mode
- Prefer functional components (React)
- Keep functions under 50 lines

## Testing
- 90%+ coverage required
- Test names: `describe('Component', () => { it('should...') })`
- Include both happy path and edge cases

## Commits
- One logical feature per commit
- Message format: `feat: <description>`
- Run tests before committing

## Tools Available
- npm (package management)
- jest (testing)
- git (version control)
```

### Project rules.toml (Safe Mode)

Override global safe mode rules for this project:
```toml
[filesystem]
allowedPaths = [
  "/path/to/project",
  "/tmp",
  "~/.cache/my-project"
]
blockedPatterns = [
  "*.key",
  "*.pem",
  ".env*"
]

[shell]
allowedCommands = [
  "npm",
  "node",
  "git",
  "curl"
]
blockedPatterns = [
  "rm.*-rf",
  "sudo",
  "curl.*|.*"
]
```

### Project prds/ Directory

Store multiple PRD files for different features:
```bash
# Structure
prds/
├── prd-auth-feature.json
├── prd-dashboard-redesign.json
├── prd-performance-optimization.json
└── prd-bugfix-modal-crash.json

# Commands
ralph-opencode prd list                          # List all PRDs
ralph-opencode prd select                        # Interactive picker
ralph-opencode --prd ./prds/prd-auth-feature.json  # Run specific PRD
```

### Project .opencode/agents/default.md

Define the agent's role within your project:
```markdown
# MyProject Coding Agent

## Identity
You are an expert software engineer working on MyProject, a collaborative
planning and communication platform built with React + TypeScript + Node.js.

## Your Mission
Implement features and fix bugs described in the PRD with high quality,
following project conventions and best practices.

## Responsibilities
1. Read and understand the PRD (user stories, acceptance criteria)
2. Analyze existing code in the src/ directory
3. Implement the smallest-possible changes
4. Write tests for new functionality
5. Verify tests pass
6. Commit with a clear message
7. Update documentation if needed

## Constraints
- Stay within the repository directory
- Don't delete files or directories
- Don't modify configuration files
- Ask for clarification if PRD is ambiguous
- Always run tests before committing
```

### Initialize Project Scaffold

```bash
cd your-project
ralph-opencode init

# Generates:
# ✓ ralph.json (with project defaults)
# ✓ opencode.json (with provider config)
# ✓ .instructions.md (agent role template)
# ✓ rules.toml (safe mode rules)
# ✓ prds/ directory (with sample.json)
# ✓ .opencode/agents/default.md (agent role)

# Then edit these files for your project, then:
ralph-opencode --prd ./prds/sample.json
```

---

## 🔄 Configuration Hierarchy Examples

### Example 1: Global Default
```bash
# Using ~/.config/ralph/ralph.json (global default)
cd ~/some-project
ralph-opencode --prd ./prd.json
# Uses: LM Studio qwen2.5-coder-32b @ 127.0.0.1:1234/v1
```

### Example 2: Project Override
```bash
# Using ./ralph.json (project override)
cd ~/my-special-project
# ./ralph.json contains:
#   "opencode": { "model": "deepseek-coder-v2", "baseUrl": "..." }

ralph-opencode --prd ./prd.json
# Uses: deepseek-coder-v2 from project config
# Global config is ignored (project takes precedence)
```

### Example 3: CLI Override
```bash
# CLI flag overrides everything
cd ~/my-special-project

ralph-opencode \
  --prd ./prd.json \
  --model claude-opus \
  --base-url https://api.anthropic.com/v1

# Uses: claude-opus from Anthropic (CLI takes precedence)
# Project config and global config both ignored
```

### Example 4: Environment Variable
```bash
# Env var overrides project and global config (but not CLI flags)
export RALPH_MODEL="mixtral-8x7b"
export RALPH_BASE_URL="https://openrouter.ai/api/v1"

cd ~/my-special-project
ralph-opencode --prd ./prd.json

# Uses: mixtral-8x7b from OpenRouter (env vars take precedence)
# Project config ignored
# But CLI flags would still override this
```

---

Settings are resolved in this order (highest priority first):

```
1. CLI Flags                    (--model, --base-url, --safe, etc.)
   ↓
2. Environment Variables        (RALPH_MODEL, RALPH_BASE_URL, etc.)
   ↓
3. Repository Config            (./ralph.json in project root)
   ↓
4. Global Config                (~/.config/ralph/ralph.json)
   ↓
5. Built-in Defaults            (Qwen 2.5 Coder 32B @ 127.0.0.1:1234/v1)
```

### Check Resolved Config
```bash
ralph-opencode config show                    # Show all settings
ralph-opencode config show --print-opencode-config  # Full OpenCode config
```

---

## 🎯 Common Workflows

### 1. Single Iteration (Development)
```bash
cd ~/my-project
ralph-opencode --prd ./prd.json
```
**What it does:**
- Runs one iteration of the Ralph loop
- Uses OpenCode to implement next incomplete story
- Logs output to `~/.local/state/ralph/logs/<repo-hash>/<date>/<time>.log`

### 2. Overnight Run (Safe Mode)
```bash
ralph-opencode --repo ~/projects/myapp \
  --prd ~/prds/feature.json \
  --until-complete \
  --safe \
  --max-hours 8 \
  --max-iterations 100
```
**Flags explained:**
- `--until-complete`: Keep running until all stories pass
- `--safe`: Enable safe mode (uses `~/.config/opencode/rules.toml`)
- `--max-hours 8`: Stop after 8 hours (wall clock)
- `--max-iterations 100`: Stop after 100 iterations
- `--max-failures 3`: Stop after 3 consecutive failures (default)

### 3. Use Custom Model (OpenRouter)
```bash
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model anthropic/claude-sonnet-4 \
  --prd ./prd.json
```

### 4. Per-Repo Configuration
Create `./ralph.json` in your project root:
```json
{
  "opencode": {
    "model": "deepseek-coder-v2",
    "baseUrl": "https://openrouter.ai/api/v1"
  },
  "loop": {
    "maxIterations": 50
  },
  "safeMode": {
    "enabled": true
  }
}
```

Then:
```bash
ralph-opencode --prd ./prd.json
# Uses repo config, overriding global defaults
```

### 5. Check System Health
```bash
ralph-opencode doctor
```
**Verifies:**
- Dependencies installed (jq, curl, opencode, git)
- Config files present
- LM Studio endpoint reachable
- Environment variables set

### 6. View Metrics
```bash
ralph-opencode metrics
# Shows: total runs, success/failure counts, p50/p95 durations
```

### 7. Project-Level Configuration
Create project-specific overrides by adding files to your repository root:

```bash
cd ~/my-project
ralph-opencode init  # Initialize project scaffold
```

**Generated structure:**
```
~/my-project/
├── ralph.json              # Project-specific Ralph config
├── opencode.json           # Project-specific OpenCode config
├── .instructions.md        # Project guidelines (optional)
├── rules.toml              # Safe mode rules override
├── prds/                   # Directory for PRD files
│   └── sample.json         # Example PRD
└── .opencode/
    └── agents/
        └── default.md      # Agent role definition
```

**Project config overrides global settings:**
```bash
# Before: uses global ~/.config/ralph/ralph.json
ralph-opencode --prd ./prd.json

# After: uses ./ralph.json (project takes precedence)
# Edit ./ralph.json in project root with:
cat > ralph.json << 'EOF'
{
  "opencode": {
    "model": "project-specific-model",
    "baseUrl": "http://localhost:1235/v1"  # Different LM Studio instance
  },
  "loop": {
    "maxIterations": 25
  }
}
EOF

ralph-opencode --prd ./prd.json
# Now uses project's model and max iterations
```

### 8. Project Instructions & Guidelines
Add agent instructions that Ralph passes to OpenCode:

```bash
cat > .instructions.md << 'EOF'
# Project Guidelines for AI Agents

## Architecture
- Use TypeScript for all new code
- Follow src/lib/utils.ts patterns for shared logic
- Keep components under 200 lines

## Testing
- Add unit tests in __tests__/ parallel to source
- Run: npm test before committing
- Coverage must stay above 80%

## Git Conventions
- Commit messages: "feat: <description>" or "fix: <description>"
- One feature per commit
- Always include test updates

## Tools Available
- npm (package management)
- jest (testing)
- prettier (formatting)

EOF
```

These guidelines are automatically provided to OpenCode on each iteration.

### 9. Manage Project PRDs
```bash
# List all PRD files in project
ralph-opencode prd list

# Interactively select and run a PRD
ralph-opencode prd select
# (prompts for selection, then runs iteration)

# Or run specific PRD
ralph-opencode --prd ./prds/feature-auth.json
```

**PRD directory structure:**
```
prds/
├── prd-feature-auth.json        # Feature PRD
├── prd-bugfix-modal.json        # Bug fix PRD
├── prd-performance.json         # Performance improvements
└── sample.json                  # Example template
```

### 10. Develop Locally with Project Config
Typical workflow for developing a feature with the agent:

```bash
cd ~/my-project

# 1. Check project setup
ralph-opencode doctor
# ✓ ralph-opencode installed
# ✓ Project config found: ./ralph.json
# ✓ PRD directory found: ./prds/
# ✓ Instructions found: .instructions.md

# 2. Create or select PRD
ralph-opencode prd list
# Available PRDs:
#   1. prd-feature-auth.json
#   2. prd-bugfix-modal.json

# 3. Run one iteration
ralph-opencode --prd ./prds/prd-feature-auth.json

# 4. Check results
git diff
git log --oneline -5

# 5. Iterate: fix issues and run again
ralph-opencode --prd ./prds/prd-feature-auth.json

# 6. When complete, run overnight safe mode
ralph-opencode --prd ./prds/prd-feature-auth.json \
  --until-complete --safe --max-hours 4
```

---

## 🔐 Secrets Management

### Option 1: Environment Variables (Highest Priority)
```bash
# In ~/.config/zsh/.env (encrypted via chezmoi)
export RALPH_API_KEY="sk-..."
export OPENROUTER_TOKEN="sk-or-..."
```

### Option 2: Secrets File
```bash
# Copy template
cp ~/.config/ralph/secrets.env.example ~/.config/ralph/secrets.env

# Edit
nvim ~/.config/ralph/secrets.env
# LMSTUDIO_API_KEY=sk-lmstudio
# OPENROUTER_TOKEN=sk-or-...

# Secure permissions
chmod 600 ~/.config/ralph/secrets.env

# Add to chezmoi
chezmoi add --encrypt ~/.config/ralph/secrets.env

# Update ralph.json to reference it
# "secrets": { "file": "${XDG_CONFIG_HOME}/ralph/secrets.env" }
```

### Option 3: macOS Keychain
```bash
security add-generic-password -a "$USER" -s "ralph-opencode" -w "your-api-key"
```

Then configure in `~/.config/ralph/ralph.json`:
```json
{
  "secrets": {
    "keychainService": "ralph-opencode"
  }
}
```

---

## 🔧 Configuration Examples

### Global Config (~/.config/ralph/ralph.json)
```json
{
  "version": "1.0.0",
  "runner": {
    "default": "opencode"
  },
  "opencode": {
    "baseUrl": "http://127.0.0.1:1234/v1",
    "model": "lmstudio/qwen2.5-coder-32b-instruct",
    "sessionMode": "fresh",
    "timeout": 600
  },
  "secrets": {
    "file": "${XDG_CONFIG_HOME}/ralph/secrets.env"
  },
  "repo": {
    "detectGitRoot": true,
    "stateLocation": "global",
    "globalStateDir": "${XDG_STATE_HOME}/ralph/runs"
  },
  "loop": {
    "maxIterations": 50,
    "maxHours": 8,
    "maxConsecutiveFailures": 3,
    "cooldownSeconds": 5,
    "untilComplete": false
  },
  "safeMode": {
    "enabled": false,
    "rules": {
      "noDeleteOutsideRepo": true,
      "noReadEnvFiles": true,
      "noNetworkCalls": false
    }
  },
  "logging": {
    "level": "info",
    "iterationLogs": true
  },
  "metrics": {
    "enabled": true,
    "storageDir": "${XDG_STATE_HOME}/ralph/metrics"
  }
}
```

### Safe Mode Rules (~/.config/opencode/rules.toml)
```toml
[filesystem]
allow = [
    "${REPO_ROOT}/**",
    "${XDG_STATE_HOME}/opencode/**"
]
deny = [
    "~/.ssh/**",
    "~/.gnupg/**",
    "**/.env*"
]

[shell]
deny = [
    "rm -rf /",
    "sudo *",
    "curl * | bash"
]

[git]
ask = [
    "git push*",
    "git reset --hard*"
]
```

---

## 🧠 LM Studio Integration

### Setup LM Studio
1. Download from [lmstudio.ai](https://lmstudio.ai)
2. Load a model (e.g., Qwen 2.5 Coder 32B)
3. Go to **Server** tab
4. Click **Start Server**
5. Default endpoint: `http://127.0.0.1:1234/v1`

### Verify Connection
```bash
ralph-opencode doctor
```

Or manually:
```bash
curl http://127.0.0.1:1234/v1/models | jq .
```

### Model Selection Guide

**Recommended for Ralph loops (by speed/quality tradeoff):**

| Model | Size | Speed | Quality | RAM | VRAM | Best For |
|-------|------|-------|---------|-----|------|----------|
| **Qwen 2.5 Coder 32B** | 32B | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 64GB | 16GB | 🥇 **Default choice** - best overall balance |
| **Deepseek Coder V2** | 236B | ⭐ | ⭐⭐⭐⭐⭐ | 128GB+ | 24GB+ | Complex tasks, unlimited budget |
| **Llama 3.1 70B** | 70B | ⭐⭐ | ⭐⭐⭐⭐⭐ | 128GB | 16GB | Complex reasoning, large projects |
| **Phi 4** | 14B | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 32GB | 8GB | Fast iterations, good quality |
| **Qwen 2.5 Coder 7B** | 7B | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | 16GB | 4GB | Laptops, quick tests, basic tasks |
| **Mixtral 8x7B** | 56B | ⭐⭐⭐ | ⭐⭐⭐⭐ | 96GB | 12GB | Good MoE balance, fast inference |

### Finding Model Names in LM Studio

```bash
# Get exact model IDs that LM Studio reports
curl http://127.0.0.1:1234/v1/models | jq '.data[].id'

# Example output:
# "lmstudio-community/Qwen2.5-Coder-32B-Instruct-GGUF"
# "deepseek-ai/deepseek-coder-236b-instruct"
# "meta-llama/Llama-3.1-70B-Instruct"
```

### Use Different Model

**From LM Studio (simplest):**
```bash
# Load model in LM Studio GUI, then run
ralph-opencode --prd ./prd.json

# It auto-detects the currently loaded model
```

**Specify explicit model name:**
```bash
# Run with specific model
ralph-opencode \
  --model deepseek-coder-v2 \
  --prd ./prd.json

# Or full model ID
ralph-opencode \
  --model "deepseek-ai/deepseek-coder-236b-instruct" \
  --prd ./prd.json
```

**Quick model switching workflow:**
```bash
# 1. Open LM Studio GUI
# 2. Search for model in Library
# 3. Click Load (waits for download + load)
# 4. Go to Server tab → Start Server
# 5. In terminal, verify:
curl http://127.0.0.1:1234/v1/models | jq '.data[].id'

# 6. Run ralph with auto-detected model
ralph-opencode --prd ./prd.json

# Or run immediately after switching:
ralph-opencode --prd ./prd.json -v  # -v shows which model was selected
```

### Practical Examples by Scenario

**🚀 Quick test (laptop, limited RAM):**
```bash
# Use 7B model for fast feedback loop
ralph-opencode \
  --model qwen2.5-coder-7b \
  --prd ./prd.json
# ~15-30 seconds per iteration
```

**⚡ Fast production run (balanced):**
```bash
# Default: Qwen 32B (best balance)
ralph-opencode --prd ./prd.json
# ~45-90 seconds per iteration, high quality
```

**🎯 Complex feature (high quality required):**
```bash
# Deepseek 236B for complex logic
ralph-opencode \
  --model deepseek-coder-v2 \
  --prd ./prd.json
# ~120-300 seconds per iteration, best quality

# Or Llama 3.1 70B (faster alternative)
ralph-opencode \
  --model "meta-llama/Llama-3.1-70B-Instruct" \
  --prd ./prd.json
```

**💰 Cloud provider (OpenRouter):**
```bash
# Using OpenRouter instead of LM Studio
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model anthropic/claude-opus \
  --prd ./prd.json

# Requires: export OPENROUTER_TOKEN="sk-or-..."
```

**🔄 Overnight safe run (with model choice):**
```bash
# Balanced speed/quality for unattended runs
ralph-opencode \
  --prd ./prd.json \
  --until-complete \
  --safe \
  --max-hours 8 \
  --model qwen2.5-coder-32b
```

### Change Default Model in Global Config

Edit `~/.config/ralph/ralph.json`:
```json
{
  "opencode": {
    "model": "deepseek-coder-v2",
    "baseUrl": "http://127.0.0.1:1234/v1"
  }
}
```

Then all future runs use deepseek by default:
```bash
ralph-opencode --prd ./prd.json
# Uses deepseek-coder-v2 automatically
```

### Set Default Model via Environment Variable

```bash
export RALPH_MODEL="qwen2.5-coder-32b"
export RALPH_BASE_URL="http://127.0.0.1:1234/v1"

# Now all runs use this model
ralph-opencode --prd ./prd.json
```

### Model Performance Benchmarks (rough estimates)

Tested on MacBook Pro M3 Max with 128GB RAM + RTX 4090:

| Model | Tokens/Sec | Time per Iteration | Memory Peak |
|-------|-----------|-------------------|------------|
| Qwen 7B | 40 tok/s | 45s | 12GB |
| Qwen 32B | 25 tok/s | 90s | 48GB |
| Phi 4 | 35 tok/s | 60s | 18GB |
| Llama 70B | 12 tok/s | 180s | 100GB |
| Deepseek 236B | 8 tok/s | 300s | 160GB |

*Speeds vary based on context length and hardware; these are typical iteration times.*

---

## 📊 Monitoring & Observability

### Real-time Logs
```bash
# Watch logs for current repo
tail -f ~/.local/state/ralph/logs/<repo-hash>/$(date +%Y%m%d)/*.log

# Or find repo hash
REPO_HASH=$(echo -n "$(pwd)" | shasum -a 256 | cut -c1-12)
tail -f ~/.local/state/ralph/logs/$REPO_HASH/*/latest.log
```

### Metrics Summary
```bash
ralph-opencode metrics
# Output:
# Total runs:     42
# Succeeded:      38
# Failed:         4
# Duration (seconds):
#   p50:          45.2
#   p95:          120.8
```

### Per-Iteration Metrics
```bash
# JSON format in:
~/.local/state/ralph/metrics/<repo-hash>/20260113*.json

# View latest
ls -lt ~/.local/state/ralph/metrics/*/  | head -5
jq . ~/.local/state/ralph/metrics/<repo-hash>/*.json | head -100
```

---

## 🐛 Debugging

### Dry Run (No Execution)
```bash
ralph-opencode --prd ./prd.json --dry-run
```

### Verbose Output
```bash
ralph-opencode --prd ./prd.json -v
```

### Print OpenCode Config
```bash
ralph-opencode config show --print-opencode-config
```

### Check Configuration Sources
```bash
ralph-opencode config show
# Shows where each setting came from
```

### Failure Marker
If max consecutive failures is reached:
```bash
cat .ralph-needs-human
# Shows timestamp and failure count
```

---

## 🛑 Troubleshooting

### "ralph-opencode: command not found"
```bash
# Ensure PATH includes ~/.local/bin
echo $PATH | grep ~/.local/bin

# If not, add to shell config
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.config/zsh/.zshrc

# Then apply again
chezmoi apply
```

### "Cannot reach endpoint: http://127.0.0.1:1234/v1"
```bash
# 1. Check LM Studio is running
curl http://127.0.0.1:1234/v1/models

# 2. Check API server is enabled in LM Studio
# Settings → Server → Start Server

# 3. Check port
lsof -i :1234
```

### "opencode command not found"
```bash
# Install OpenCode
# See: https://opencode.dev/docs/installation

# On macOS:
brew install opencode

# Verify
which opencode
```

### Config Not Applied
```bash
# 1. Check JSON syntax
jq . ~/.config/ralph/ralph.json

# 2. Check precedence
ralph-opencode config show

# 3. Verify file exists
ls -la ~/.config/ralph/ralph.json

# 4. Check permissions
chmod 644 ~/.config/ralph/ralph.json
```

### Secrets Not Loading
```bash
# 1. Check file permissions (must be 0600)
ls -la ~/.config/ralph/secrets.env

# 2. Fix if needed
chmod 600 ~/.config/ralph/secrets.env

# 3. Check format (KEY=VALUE, no export)
cat ~/.config/ralph/secrets.env

# 4. Test loading
bash -x ~/.config/ralph/secrets.env
```

---

## 📖 Common Commands

```bash
# Installation & Verification
chezmoi apply                           # Install all configs
ralph-opencode doctor                   # System health check
ralph-opencode config show              # Show all settings

# Running Iterations
ralph-opencode --prd ./prd.json         # Single iteration
ralph-opencode --prd ./prd.json -v      # Verbose output
ralph-opencode --prd ./prd.json --dry-run  # Test without running

# Configuration
ralph-opencode config show --print-opencode-config
ralph-opencode init                     # Initialize repo config

# Monitoring
ralph-opencode metrics                  # View aggregated stats
tail -f ~/.local/state/ralph/logs/*/latest.log  # Watch logs

# Editing (via chezmoi)
chezmoi edit ~/.config/ralph/ralph.json
chezmoi edit ~/.config/opencode/opencode.json
chezmoi edit ~/.local/bin/executable_ralph-opencode

# Environment Setup
export RALPH_MODEL="deepseek-coder-v2"
export RALPH_BASE_URL="https://openrouter.ai/api/v1"
export RALPH_API_KEY="sk-or-..."
```

---

## 🎯 Comprehensive Command Examples

### Basic Workflows

**1. First-time setup:**
```bash
# Apply all dotfiles and configs
chezmoi apply

# Verify installation
ralph-opencode doctor

# Check resolved configuration
ralph-opencode config show
```

**2. Single quick iteration (development):**
```bash
cd ~/my-project
ralph-opencode --prd ./prd.json
```

**3. Watch the logs in real-time:**
```bash
# Terminal 1: run iteration
cd ~/my-project
ralph-opencode --prd ./prd.json

# Terminal 2: watch logs
REPO_HASH=$(echo -n "$(pwd)" | shasum -a 256 | cut -c1-12)
tail -f ~/.local/state/ralph/logs/$REPO_HASH/*/latest.log
```

**4. View what ralph will do (dry run):**
```bash
ralph-opencode --prd ./prd.json --dry-run
```

**5. Verbose output to debug issues:**
```bash
ralph-opencode --prd ./prd.json -v
```

### Model Selection Examples

**6. Use Qwen 7B for fast feedback (laptop):**
```bash
ralph-opencode \
  --model qwen2.5-coder-7b \
  --prd ./prd.json
```

**7. Use Deepseek for complex logic:**
```bash
ralph-opencode \
  --model deepseek-coder-v2 \
  --prd ./prd.json
```

**8. Use Llama 70B (alternative to Deepseek):**
```bash
ralph-opencode \
  --model "meta-llama/Llama-3.1-70B-Instruct" \
  --prd ./prd.json
```

**9. Use Phi 4 for balanced speed/quality:**
```bash
ralph-opencode \
  --model "microsoft/phi-4" \
  --prd ./prd.json
```

**10. Check which models are available:**
```bash
curl http://127.0.0.1:1234/v1/models | jq '.data[] | {id: .id, owned_by: .owned_by}'
```

### Unattended Runs

**11. Overnight run (safe mode, 8 hours max):**
```bash
ralph-opencode \
  --prd ./prd.json \
  --until-complete \
  --safe \
  --max-hours 8
```

**12. Aggressive overnight run (no time limit, max iterations):**
```bash
ralph-opencode \
  --prd ./prd.json \
  --until-complete \
  --safe \
  --max-iterations 150 \
  --model qwen2.5-coder-32b
```

**13. Run with specific repo path (from anywhere):**
```bash
ralph-opencode \
  --repo ~/projects/myapp \
  --prd ~/projects/myapp/prds/feature.json \
  --until-complete \
  --safe \
  --max-hours 4
```

**14. Stop after 3 failures (default behavior):**
```bash
ralph-opencode \
  --prd ./prd.json \
  --until-complete \
  --safe \
  --max-failures 3
```

### Using Cloud APIs

**15. Use OpenRouter (Claude):**
```bash
# Set up environment
export OPENROUTER_TOKEN="sk-or-xxx"

# Run with Claude Opus
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model "anthropic/claude-opus" \
  --prd ./prd.json
```

**16. Use OpenRouter (multiple model options):**
```bash
# DeepSeek from OpenRouter
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model "deepseek/deepseek-coder" \
  --prd ./prd.json

# Mistral
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model "mistralai/mixtral-8x7b" \
  --prd ./prd.json
```

**17. Use Anthropic API (if subscribed):**
```bash
export ANTHROPIC_API_KEY="sk-ant-xxx"

ralph-opencode \
  --base-url https://api.anthropic.com/v1 \
  --model "claude-opus-4-1" \
  --prd ./prd.json
```

**18. Use OpenAI API:**
```bash
export OPENAI_API_KEY="sk-xxx"

ralph-opencode \
  --base-url https://api.openai.com/v1 \
  --model "gpt-4-turbo" \
  --prd ./prd.json
```

### Project Configuration

**19. Initialize project with defaults:**
```bash
cd ~/my-project
ralph-opencode init

# Creates:
# - ralph.json
# - opencode.json
# - .instructions.md
# - rules.toml
# - prds/
# - .opencode/agents/default.md
```

**20. Override just the model for this project:**
```bash
cat > ~/my-project/ralph.json << 'EOF'
{
  "opencode": {
    "model": "deepseek-coder-v2"
  }
}
EOF

cd ~/my-project
ralph-opencode --prd ./prd.json
# Uses Deepseek for this project only
```

**21. Override multiple settings per project:**
```bash
cat > ~/my-project/ralph.json << 'EOF'
{
  "opencode": {
    "model": "llama-3.1-70b",
    "baseUrl": "https://openrouter.ai/api/v1"
  },
  "loop": {
    "maxIterations": 25,
    "cooldownSeconds": 10
  },
  "safeMode": {
    "enabled": true
  }
}
EOF

ralph-opencode --prd ./prd.json
# Uses project settings: Llama 70B, 25 max iterations, safe mode enabled
```

**22. Set global defaults (all projects):**
```bash
cat > ~/.config/ralph/ralph.json << 'EOF'
{
  "opencode": {
    "model": "qwen2.5-coder-32b",
    "baseUrl": "http://127.0.0.1:1234/v1"
  },
  "loop": {
    "maxIterations": 50
  }
}
EOF

# Now all projects use Qwen 32B unless they override it
```

### Environment Variables (for CI/CD or scripts)

**23. Set model via environment variable:**
```bash
export RALPH_MODEL="qwen2.5-coder-7b"
export RALPH_BASE_URL="http://127.0.0.1:1234/v1"

ralph-opencode --prd ./prd.json
# Uses 7B model for this session
```

**24. Use environment variables for API keys:**
```bash
export RALPH_API_KEY="sk-xxx"
export OPENROUTER_TOKEN="sk-or-xxx"
export ANTHROPIC_API_KEY="sk-ant-xxx"

ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model "anthropic/claude-opus" \
  --prd ./prd.json
# Automatically picks up keys from environment
```

**25. CI/CD example (GitHub Actions):**
```bash
#!/bin/bash
export RALPH_MODEL="qwen2.5-coder-32b"
export RALPH_BASE_URL="http://127.0.0.1:1234/v1"

ralph-opencode \
  --prd ./prd.json \
  --until-complete \
  --safe \
  --max-hours 2 \
  --max-iterations 25
```

### PRD Management

**26. List available PRDs:**
```bash
ralph-opencode prd list
```

**27. Interactively select and run a PRD:**
```bash
ralph-opencode prd select
# Presents menu, runs selected PRD
```

**28. Run specific PRD by name:**
```bash
ralph-opencode --prd ./prds/prd-feature-auth.json
```

**29. Create project PRD structure:**
```bash
mkdir -p ~/my-project/prds

cat > ~/my-project/prds/feature-auth.json << 'EOF'
{
  "title": "Implement Authentication",
  "description": "Add OAuth2 and session management",
  "stories": [
    {
      "id": "auth-1",
      "title": "Add OAuth2 sign-up",
      "acceptance": ["Users can sign up with GitHub"]
    }
  ]
}
EOF

# Run it
ralph-opencode --prd ./prds/feature-auth.json
```

**30. Run all PRDs in sequence:**
```bash
for prd in ~/my-project/prds/*.json; do
  echo "Running $prd..."
  ralph-opencode --prd "$prd" --until-complete --safe
done
```

### Monitoring & Debugging

**31. Check system health:**
```bash
ralph-opencode doctor
# Shows: installed deps, config files, LM Studio connection, env vars
```

**32. View current configuration:**
```bash
ralph-opencode config show
```

**33. View full OpenCode config:**
```bash
ralph-opencode config show --print-opencode-config
```

**34. View aggregated metrics:**
```bash
ralph-opencode metrics
# Shows: total runs, success rate, p50/p95 durations
```

**35. Follow logs in real-time:**
```bash
# Get repo hash
REPO_HASH=$(echo -n "$(pwd)" | shasum -a 256 | cut -c1-12)

# Watch latest logs
tail -f ~/.local/state/ralph/logs/$REPO_HASH/$(date +%Y%m%d)/*.log
```

**36. View JSON metrics:**
```bash
ls -lt ~/.local/state/ralph/metrics/$REPO_HASH/ | head -5
jq . ~/.local/state/ralph/metrics/$REPO_HASH/20260113*.json | head -50
```

**37. Check if human intervention is needed:**
```bash
# After max failures reached
cat .ralph-needs-human
# Shows timestamp and failure details
```

### Advanced Workflows

**38. Test config before running (dry run with verbose):**
```bash
ralph-opencode --prd ./prd.json --dry-run -v
```

**39. Run with cooldown between iterations (give LM Studio a break):**
```bash
cat > ~/my-project/ralph.json << 'EOF'
{
  "loop": {
    "cooldownSeconds": 30
  }
}
EOF

ralph-opencode --prd ./prd.json --until-complete --safe
```

**40. Compare two models on same task:**
```bash
# Run with Qwen
time ralph-opencode --model qwen2.5-coder-32b --prd ./prd.json
git diff
git reset --hard

# Run with Phi
time ralph-opencode --model "microsoft/phi-4" --prd ./prd.json
git diff
git reset --hard

# Run with Deepseek
time ralph-opencode --model deepseek-coder-v2 --prd ./prd.json
```

**41. Safe mode for unattended runs:**
```bash
# Copy and customize rules
cp ~/.config/opencode/rules.toml ~/my-project/rules.toml
nvim ~/my-project/rules.toml

# Run with project-level safe mode rules
ralph-opencode --prd ./prd.json --until-complete --safe
```

**42. Custom instructions per project:**
```bash
cat > ~/my-project/.instructions.md << 'EOF'
# MyApp Development Guidelines

## Code Style
- Use TypeScript strict mode
- Prefer const over let/var
- Keep functions under 100 lines

## Testing
- Write tests for all new code
- Minimum 80% coverage
- Run: npm test before git commit

## Git
- Commit messages: "feat:" or "fix:" prefix
- One feature per commit
- Keep commits small and reviewable
EOF

ralph-opencode --prd ./prd.json
# OpenCode automatically reads and follows these guidelines
```

### Editing Configs

**43. Edit global Ralph config (opens in $EDITOR):**
```bash
chezmoi edit ~/.config/ralph/ralph.json

# Or directly
nvim ~/.config/ralph/ralph.json
```

**44. Edit global OpenCode config:**
```bash
chezmoi edit ~/.config/opencode/opencode.json
nvim ~/.config/opencode/opencode.json
```

**45. Sync changes back to chezmoi:**
```bash
# After manual edits, re-add to chezmoi
chezmoi add ~/.config/ralph/ralph.json
chezmoi add ~/.config/opencode/opencode.json

# Apply to verify
chezmoi apply
```

### Troubleshooting Commands

**46. Test LM Studio connection:**
```bash
curl http://127.0.0.1:1234/v1/models | jq .
curl -X POST http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-32b",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }' | jq .
```

**47. Verify PATH includes .local/bin:**
```bash
echo $PATH | grep ~/.local/bin
which ralph-opencode
```

**48. Check config file syntax:**
```bash
jq . ~/.config/ralph/ralph.json
jq . ~/.config/opencode/opencode.json
```

**49. Verify installed dependencies:**
```bash
which opencode
which jq
which curl
which git
ralph-opencode doctor
```

**50. Debug secrets loading:**
```bash
# Check file exists and has correct permissions
ls -la ~/.config/ralph/secrets.env

# Verify format (KEY=VALUE, no export)
cat ~/.config/ralph/secrets.env

# Test by running doctor
ralph-opencode doctor
```

---

## 🎓 Key Concepts

### Configuration Hierarchy
- **CLI flags**: Highest priority, used for one-off overrides
- **Environment variables**: Useful for CI/CD and scripts
- **Repo config**: Project-specific settings in `./ralph.json`
- **Global config**: System-wide defaults in `~/.config/ralph/ralph.json`
- **Built-in defaults**: Fallbacks when nothing else is set

### Safe Mode
- Blocks filesystem access outside repo
- Denies dangerous shell commands
- Restricts network to allowlist
- Requires confirmation for git operations
- Perfect for unattended overnight runs

### Per-Repo State
- Uses SHA-256 hash of repo path for isolation
- Keeps logs, metrics, and state separate
- Allows multiple repos to run independently
- Cleans up automatically based on retention policy

### Metrics
- Recorded per iteration (JSON format)
- Aggregates success rate, p50/p95 durations
- Local-only (no telemetry by default)
- Useful for tuning model choice and stop conditions

---

## 📚 Additional Resources

- **Setup Guide**: `docs/ai-tools/ralph-opencode-setup.md`
- **LM Studio**: https://lmstudio.ai
- **OpenRouter**: https://openrouter.ai
- **Chezmoi Docs**: https://www.chezmoi.io
- **OpenCode Docs**: https://opencode.dev
