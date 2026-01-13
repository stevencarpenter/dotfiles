# Ralph + OpenCode: Project-Level Configuration Upgrade

## What's New (v2.0)

This release adds comprehensive **project-level configuration support** to Ralph + OpenCode, enabling per-repository customization while maintaining global system defaults.

### ✨ Major Features

#### 1. Project Auto-Detection
Ralph now automatically detects and uses project-level configurations:

```bash
cd your-project
# If ./ralph.json exists, it automatically overrides ~/.config/ralph/ralph.json
ralph-opencode --prd ./prd.json
```

#### 2. Project Scaffolding
Initialize a complete project structure with one command:

```bash
ralph-opencode init
# Creates:
# ✓ ralph.json (project config)
# ✓ opencode.json (OpenCode config)
# ✓ .instructions.md (agent guidelines)
# ✓ rules.toml (safe mode rules)
# ✓ prds/ directory with sample
# ✓ .opencode/agents/default.md (agent role)
```

#### 3. PRD Management
Store and manage multiple PRDs per project:

```bash
ralph-opencode prd list          # List all project PRDs
ralph-opencode prd select        # Interactive picker → runs iteration
```

#### 4. Project Instructions
Add project guidelines that Ralph passes to agents:

```bash
# Create .instructions.md with:
# - Code style requirements
# - Testing standards
# - Commit conventions
# - Available tools
# - Constraints and guardrails
```

#### 5. Three-Tier Configuration
Clear precedence for all configuration:

```
CLI Flags > Environment Variables > Project Config > Global Config > Defaults
```

## 📁 Project Structure

Projects can now optionally contain:

```
your-project/
├── ralph.json                 # Project Ralph config
├── opencode.json              # Project OpenCode config
├── .instructions.md           # Agent guidelines
├── rules.toml                 # Safe mode rules
├── prds/                      # Project PRD storage
│   ├── prd-feature-a.json
│   └── prd-feature-b.json
└── .opencode/
    └── agents/
        └── default.md         # Agent role
```

**All files are optional.** Projects work with global defaults if not present.

## 🔄 Migration Path

### If You're Using Global Configuration Only

No changes needed! Everything works as before:

```bash
# Still works exactly the same
ralph-opencode --prd ./prd.json
ralph-opencode doctor
ralph-opencode config show
```

### If You Want Project-Specific Configuration

1. Navigate to your project:
   ```bash
   cd your-project
   ```

2. Initialize the scaffold:
   ```bash
   ralph-opencode init
   ```

3. Customize the generated files:
   ```bash
   # Edit ralph.json for project-specific model/baseUrl
   # Edit .instructions.md for project guidelines
   # Add PRD files to prds/ directory
   ```

4. Run with project config:
   ```bash
   ralph-opencode prd select    # Interactive picker
   # or
   ralph-opencode --prd ./prds/feature.json
   ```

## 📊 Comparison

### v1.0 (Original)
- Global configuration only
- Basic commands: run, doctor, metrics
- Manual PRD selection
- 754 lines

### v2.0 (New)
- Global + project + CLI configuration
- Enhanced commands: +init, +prd list, +prd select
- Interactive PRD management
- Project scaffolding
- Project instructions
- 996 lines (+30%)
- **100% backward compatible**

## 🚀 Getting Started

### 1. Update Your Dotfiles
```bash
chezmoi apply
ralph-opencode doctor  # Verify
```

### 2. Try It On an Existing Project
```bash
cd ~/existing-project
ralph-opencode init
# Review the generated files
# Edit ralph.json to match your needs
```

### 3. Run a Simple Test
```bash
ralph-opencode prd list        # See what PRDs exist
ralph-opencode prd select      # Pick one and run
```

## 📚 Documentation

### Quick Reference
→ `RALPH_OPENCODE_CHEATSHEET.md` (981 lines)
- Quick start
- Conventions
- Workflows
- Configuration examples
- Troubleshooting

### Detailed Setup
→ `docs/ai-tools/ralph-opencode-setup.md` (504 lines)
- Installation
- Configuration guide
- Project setup
- Safe mode rules
- Examples

## ⚙️ Configuration Precedence

Understanding how configs are selected (in priority order):

1. **CLI Flags** (highest priority)
   ```bash
   ralph-opencode --model claude-opus --base-url https://...
   ```

2. **Environment Variables**
   ```bash
   export RALPH_MODEL="deepseek-coder"
   export RALPH_BASE_URL="http://localhost:1234/v1"
   ```

3. **Project Config** (./ralph.json in repo root)
   ```json
   {
     "opencode": {
       "model": "deepseek-coder-v2",
       "baseUrl": "http://localhost:1234/v1"
     }
   }
   ```

4. **Global Config** (~/.config/ralph/ralph.json)
   ```json
   { /* system-wide defaults */ }
   ```

5. **Built-in Defaults** (lowest priority)
   - Model: qwen2.5-coder-32b
   - Base URL: http://127.0.0.1:1234/v1

## 🔍 Debugging

Check which configuration is being used:

```bash
ralph-opencode config show
# Shows resolved values from all layers
```

Verify project detection:

```bash
cd your-project
ralph-opencode config show
# Shows which configs are loaded from project vs global
```

## ❓ FAQ

### Q: Do I need to update all my projects?
A: No. Old projects continue to work with global config. Add project config only when needed.

### Q: Can I use both global and project config together?
A: Yes! Project config overrides only the fields you customize. Other fields use global defaults.

### Q: How do I store secrets securely?
A: Use environment variables (highest precedence) or encrypted dotfiles via chezmoi.

### Q: Can I run overnight with project config?
A: Yes! Use `--safe` flag with project `rules.toml` for safe unattended runs.

### Q: What if I want global defaults to apply?
A: Simply don't create project config files. Global defaults will be used automatically.

## 🔗 Related Documentation

- **Configuration Precedence**: RALPH_OPENCODE_CHEATSHEET.md → Section: "Configuration Precedence"
- **Project Setup**: docs/ai-tools/ralph-opencode-setup.md → Section: "Per-Repo Configuration"
- **Safe Mode**: docs/ai-tools/ralph-opencode-setup.md → Section: "Safe Mode for Overnight Runs"
- **Examples**: RALPH_OPENCODE_CHEATSHEET.md → Section: "Common Workflows"

## 📞 Support

### Commands
```bash
ralph-opencode --help          # Show all commands
ralph-opencode doctor          # System health check
ralph-opencode init            # Generate project scaffold
ralph-opencode config show     # Show resolved config
```

### Documentation
- Quick reference: `RALPH_OPENCODE_CHEATSHEET.md`
- Detailed setup: `docs/ai-tools/ralph-opencode-setup.md`
- This file: `UPGRADE_NOTES.md`

## ✅ Version Info

- **Version**: 2.0
- **Release Date**: January 2025
- **Compatibility**: 100% backward compatible with v1.0
- **Status**: Production Ready

---

**Ready to upgrade?** Run `chezmoi apply` and then try `ralph-opencode init` in any project!
