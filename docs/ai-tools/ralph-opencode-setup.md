# Ralph + OpenCode: Chezmoi Integration Guide

This document describes how Ralph and OpenCode are configured in your chezmoi-managed dotfiles, providing global defaults with per-repo override capabilities.

## Quick Start

After `chezmoi apply`, you'll have:

```bash
# Global wrapper available anywhere
ralph-opencode --help

# Check system health
ralph-opencode doctor

# Show resolved configuration
ralph-opencode config show

# Run against any repo
ralph-opencode --repo /path/to/project --prd ./prd.json
```

## File Locations

### Chezmoi Source Files

```
~/.local/share/chezmoi/
├── dot_config/
│   ├── opencode/
│   │   ├── opencode.json.tmpl    # OpenCode global config (template)
│   │   └── rules.toml            # Safe mode permission rules
│   └── ralph/
│       ├── ralph.json.tmpl       # Ralph global config (template)
│       └── secrets.env.example   # Example secrets file
└── dot_local/
    └── bin/
        └── executable_ralph-opencode  # CLI wrapper script
```

### Installed Locations (after `chezmoi apply`)

```
~/.config/
├── opencode/
│   ├── opencode.json      # OpenCode configuration
│   ├── rules.toml         # Permission rules for safe mode
│   ├── agents/            # Custom agent definitions
│   └── commands/          # Custom commands
└── ralph/
    ├── ralph.json         # Ralph configuration
    └── secrets.env        # Encrypted secrets (optional)

~/.local/bin/
└── ralph-opencode         # Global CLI wrapper

~/.local/state/
└── ralph/
    ├── logs/              # Iteration logs
    ├── metrics/           # Performance metrics
    └── runs/              # Per-repo state
```

## Configuration Precedence

Settings are resolved in this order (highest priority first):

1. **CLI flags**: `--model`, `--base-url`, etc.
2. **Environment variables**: `RALPH_MODEL`, `RALPH_BASE_URL`, etc.
3. **Repo config**: `./ralph.json` in the target repository
4. **Global config**: `~/.config/ralph/ralph.json`
5. **Built-in defaults**: Hardcoded fallbacks in the wrapper script

## Using LM Studio

LM Studio provides an OpenAI-compatible API for local model inference:

1. **Start LM Studio** and load a model (e.g., Qwen 2.5 Coder)
2. **Enable the API server** (default: `http://127.0.0.1:1234/v1`)
3. **Verify connectivity**:
   ```bash
   ralph-opencode doctor
   ```
4. **Run iterations**:
   ```bash
   ralph-opencode --prd ./prd.json --model qwen2.5-coder-32b-instruct
   ```

## Secrets Management

### Option 1: Chezmoi Encrypted File (Recommended)

1. Create the secrets file:
   ```bash
   cp ~/.config/ralph/secrets.env.example ~/.config/ralph/secrets.env
   nvim ~/.config/ralph/secrets.env  # Add your keys
   chmod 600 ~/.config/ralph/secrets.env
   ```

2. Add to chezmoi with encryption:
   ```bash
   chezmoi add --encrypt ~/.config/ralph/secrets.env
   ```

3. Configure Ralph to use it (`~/.config/ralph/ralph.json`):
   ```json
   {
     "secrets": {
       "file": "${XDG_CONFIG_HOME}/ralph/secrets.env"
     }
   }
   ```

### Option 2: Environment Variables

Export directly in your shell config:

```bash
# In ~/.config/zsh/.env (encrypted via chezmoi)
export RALPH_API_KEY="sk-..."
export OPENROUTER_TOKEN="sk-or-..."
```

### Option 3: macOS Keychain (Optional)

Configure in `ralph.json`:

```json
{
  "secrets": {
    "keychainService": "ralph-opencode"
  }
}
```

Then store keys:
```bash
security add-generic-password -a "$USER" -s "ralph-opencode" -w "your-api-key"
```

## Per-Repo Configuration

### Project Initialization (NEW)

Ralph now supports automatic project initialization with scaffolding:

```bash
cd your-project
ralph-opencode init

# Generates:
# ✓ ralph.json (project config template)
# ✓ opencode.json (project OpenCode config)
# ✓ .instructions.md (agent guidelines)
# ✓ rules.toml (safe mode overrides)
# ✓ prds/ directory with sample.json
# ✓ .opencode/agents/default.md (agent role)
```

This creates a complete project scaffold with sensible defaults.

### Manual Project Configuration

Create a `ralph.json` in your repository root to override global settings:

```json
{
  "$schema": "https://ralph.dev/schema/config.json",
  "opencode": {
    "model": "deepseek/deepseek-coder",
    "baseUrl": "https://openrouter.ai/api/v1"
  },
  "loop": {
    "maxIterations": 100,
    "maxConsecutiveFailures": 5
  },
  "safeMode": {
    "enabled": true
  }
}
```

### Project Instructions & Guidelines

Add a `.instructions.md` file (or `AGENTS.md` or `CLAUDE.md`) with agent guidelines:

```markdown
# Project Agent Guidelines

## Context
This is a TypeScript React application for collaborative project management.

## Your Task
Implement features from the PRD with high quality and comprehensive testing.

## Code Standards
- Use TypeScript strict mode
- Functional React components only
- Max 50 lines per function
- All functions must have JSDoc comments

## Testing Requirements
- Minimum 90% coverage
- Jest test suite
- E2E tests with Playwright for critical flows

## Commit Standards
- Format: `feat: <description>` or `fix: <description>`
- One logical feature per commit
- Always include test updates

## Available Tools
- npm (package management)
- jest (testing)
- prettier (formatting)
- git (version control)

## Constraints
- No modifications to infrastructure code
- Don't delete existing tests
- Always run the test suite before committing
- Ask for clarification if requirements are ambiguous
```

Ralph automatically provides these guidelines to OpenCode on each iteration.

### Project PRDs (NEW)

Store multiple PRD files in your project's `prds/` directory:

```bash
# Initialize creates an empty prds/ directory
ralph-opencode init

# Create or copy PRD files
cp ~/prd-templates/prd-feature.json prds/prd-auth.json
cp ~/prd-templates/prd-bugfix.json prds/prd-modal-crash.json

# List available PRDs
ralph-opencode prd list
# Output:
#   1. prd-auth.json
#   2. prd-modal-crash.json

# Interactively select a PRD and run
ralph-opencode prd select
# Prompts: Which PRD? [1-2]: 1
# Runs iteration against selected PRD

# Or run specific PRD
ralph-opencode --prd ./prds/prd-auth.json
```

### Configuration Precedence

Project configs override global configs in this order:

```
1. CLI Flags                       (highest precedence)
   ↓
2. Environment Variables           (e.g., RALPH_MODEL)
   ↓
3. Project Config                  (./ralph.json in repo root)
   ↓
4. Global Config                   (~/.config/ralph/ralph.json)
   ↓
5. Built-in Defaults               (lowest precedence)
```

**Example:**
```bash
# Uses global config (unless project ralph.json exists)
ralph-opencode --prd ./prd.json

# If project ./ralph.json has "model": "deepseek-coder-v2"
# that overrides the global model setting

# But CLI flags always win:
ralph-opencode --prd ./prd.json --model claude-opus
# Uses claude-opus regardless of project or global config
```

### Project Safe Mode Rules

Create a `rules.toml` file in your project to override safe mode rules:

```toml
[filesystem]
# Allow access to specific directories
allowedPaths = [
  "/path/to/project",
  "/tmp",
  "~/.cache/my-project"
]

# Block sensitive patterns
blockedPatterns = [
  "*.key",
  "*.pem",
  ".env*",
  ".secrets"
]

[shell]
# Whitelist safe commands
allowedCommands = [
  "npm",
  "node",
  "git",
  "curl",
  "wget"
]

# Block dangerous patterns
blockedPatterns = [
  "rm.*-rf",
  "sudo",
  "curl.*|.*"
]

[git]
# Require confirmation for these operations
requiresConfirmation = [
  "push",
  "reset --hard",
  "rebase"
]
```

## Safe Mode for Overnight Runs

Enable safe mode for unattended execution:

```bash
ralph-opencode --prd ./prd.json --until-complete --safe --max-hours 8
```

Safe mode applies restrictions from `~/.config/opencode/rules.toml`:

- **Filesystem**: No access to `~/.ssh`, `~/.gnupg`, `.env` files
- **Shell**: Blocks dangerous commands (`rm -rf /`, `sudo`, `curl | bash`)
- **Git**: Requires confirmation for `push`, `reset --hard`, `rebase`
- **Network**: Restricts to known hosts (GitHub, npm, PyPI, etc.)

## Observability & Metrics

### View Run Metrics

```bash
ralph-opencode metrics
```

Output includes:
- Total runs, success/failure counts
- p50/p95 iteration durations

### Iteration Logs

Located at: `~/.local/state/ralph/logs/<repo-hash>/<date>/`

Each iteration produces a timestamped log file.

## Chezmoi Workflow

### Initial Setup

```bash
# Clone dotfiles
chezmoi init git@github.com:yourusername/dotfiles.git

# Apply (installs ralph-opencode and configs)
chezmoi apply

# Verify
ralph-opencode doctor
```

### Modifying Configuration

```bash
# Edit the template
chezmoi edit ~/.config/ralph/ralph.json

# Apply changes
chezmoi apply

# Verify
ralph-opencode config show
```

### Template Variables

The templates support chezmoi data variables:

```toml
# In ~/.config/chezmoi/chezmoi.toml
[data]
opencode_model = "deepseek/deepseek-coder"
opencode_base_url = "https://openrouter.ai/api/v1"
ralph_opencode_model = "deepseek/deepseek-coder"
ralph_opencode_base_url = "https://openrouter.ai/api/v1"
```

## CLI Reference

```bash
ralph-opencode [OPTIONS] [COMMAND]

COMMANDS:
  run             Run Ralph loop (default)
  config show     Print resolved configuration
  config check    Verify endpoint connectivity
  init            Initialize config in current directory
  doctor          System health check
  metrics         Show metrics summary

OPTIONS:
  --runner <runner>       Runner: opencode, claude, codex [default: opencode]
  --repo <path>           Target repository path [default: .]
  --prd <path>            Path to PRD JSON file [required for run]

  --model <model>         Model identifier
  --base-url <url>        API endpoint URL
  --api-key <key>         API key (prefer RALPH_API_KEY env var)

  --max-iterations <n>    Maximum iterations [default: 50]
  --max-hours <n>         Maximum runtime hours [default: 8]
  --max-failures <n>      Consecutive failures before stop [default: 3]
  --cooldown <seconds>    Delay between iterations [default: 5]
  --until-complete        Run until all stories pass

  --safe                  Enable safe mode
  --rules <path>          Custom rules file

  --verbose, -v           Verbose output
  --dry-run               Show commands without executing
  --help, -h              Show help
  --version               Show version
```

## Examples

### Single Iteration

```bash
ralph-opencode --prd ./prd.json
```

### Overnight Run with Safe Mode

```bash
ralph-opencode \
  --repo ~/projects/myapp \
  --prd ~/prds/feature.json \
  --until-complete \
  --safe \
  --max-hours 8 \
  --max-iterations 100
```

### Using OpenRouter Cloud Models

```bash
ralph-opencode \
  --base-url https://openrouter.ai/api/v1 \
  --model anthropic/claude-sonnet-4 \
  --prd ./prd.json
```

### Show Effective Configuration

```bash
ralph-opencode config show
ralph-opencode config show --print-opencode-config
```

## Troubleshooting

### "opencode command not found"

Install OpenCode:
```bash
# Check installation docs at https://opencode.dev
brew install opencode  # or appropriate method
```

### "Cannot reach endpoint"

1. Verify LM Studio is running
2. Check the API server is enabled in LM Studio settings
3. Verify the port (default: 1234)
4. Run: `curl http://127.0.0.1:1234/v1/models`

### Secrets Not Loading

1. Check file permissions: `ls -la ~/.config/ralph/secrets.env`
2. Ensure 0600 permissions: `chmod 600 ~/.config/ralph/secrets.env`
3. Verify format (KEY=VALUE, one per line, no `export`)

### Configuration Not Applied

1. Run `ralph-opencode config show` to see resolved values
2. Check precedence (CLI > env > repo > global > defaults)
3. Verify JSON syntax: `jq . ~/.config/ralph/ralph.json`
