# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and Codex (`AGENTS.md` is a symlink to this file) when
working in this repo. Global personal preferences live in `~/.claude/CLAUDE.md`; do not duplicate
them here.

## What This Is

A personal dotfiles repository managed by [Chezmoi](https://www.chezmoi.io/) for macOS. Secrets are
encrypted with age (key sourced from 1Password). The repo also vendors three small Python tools
(`mcp_sync/`, `aws_config_gen/`, `token_auditor/`) that ship alongside the dotfiles.

## Commands

All Python commands run from the repo root. Each tool is its own `uv` project.

All three Python tools use PEP 735 `[dependency-groups]`; install dev deps with `--group dev`.

### MCP Sync (`mcp_sync/`)

```bash
# Lint
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests

# Test
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
uv run --project mcp_sync --group dev pytest mcp_sync/tests/test_sync_mcp_configs.py -v  # single file

# Run sync manually
uv run --project mcp_sync sync-mcp-configs
```

### AWS Config Gen (`aws_config_gen/`)

```bash
# Lint
uv run --project aws_config_gen --group dev ruff check aws_config_gen/src aws_config_gen/tests
uv run --project aws_config_gen --group dev ruff format --check aws_config_gen/src aws_config_gen/tests

# Test
uv run --project aws_config_gen --group dev pytest aws_config_gen/tests --cov=aws_config_gen --cov-report=term-missing

# Run
uv run --project aws_config_gen aws-config-gen
```

### Token Auditor (`token_auditor/`)

```bash
cd token_auditor
uv sync --locked --group dev
uv run ruff check .
uv run ruff format --check .
uv run ty check .
uv run pytest -v          # 100% coverage required
uv run token-auditor --help   # or `uv run codax --help`
```

### Chezmoi

```bash
chezmoi diff          # Preview changes
chezmoi apply         # Apply dotfiles (triggers MCP sync automatically)
chezmoi apply -v      # Apply with verbose output
chezmoi add <file>    # Track a new file
chezmoi add --encrypt <file>  # Track with encryption
```

### Pre-commit

```bash
pre-commit run --all-files
```

## Architecture

### Chezmoi Naming Conventions

Source files use Chezmoi prefixes that transform on apply:
- `dot_` → `.` (e.g., `dot_config/` → `~/.config/`)
- `encrypted_` → decrypted via age
- `executable_` → chmod +x
- `.tmpl` suffix → Go template with variable substitution
- `run_after_` → script that runs after apply
- `run_once_` → script that runs only on first apply

### MCP Sync System (`mcp_sync/`)

The sync tool reads `dot_config/mcp/mcp-master.json` and generates tool-specific configs:

- **Master config**: `dot_config/mcp/mcp-master.json` — shared servers deployed to all machines
- **Machine overlays**: `dot_config/mcp/machine/{work.json,personal.json.tmpl,lab.json.tmpl}` — machine-type-specific
  servers (e.g., AWS MCP on work only), deployed conditionally by chezmoi
- **Templates**: `mcp_sync/src/mcp_sync/templates/` — base config templates per tool
- **Transform functions** in `sync.py`: `transform_to_copilot_format()`, `transform_to_generic_mcp_format()`,
  `transform_to_mcpservers_format()`, `transform_to_opencode_format()`
- **Merge order**: base template + master + machine overlay + per-tool overrides (later values win).
  The overrides layer is wired in `sync.py` — each target reads `~/.config/mcp/overrides/<key>.json`
  at sync time — but no override files are managed in-repo yet (`dot_config/mcp/overrides/` does not
  exist; the deployed `~/.config/mcp/overrides/` dir is present but empty).

The sync runs automatically after `chezmoi apply` via `.chezmoiscripts/run_after_sync-mcp.sh.tmpl`.
The hook selects the overlay for the deployed machine type (rendered from `.machine`, mirroring the
skills sync) and passes it via `--machine-config` — it does not glob whatever overlay sorts first on
disk, so a stale overlay left by a machine-type change can't be picked up.

#### Machine-Type Gating

Configuration is gated by machine type via chezmoi's `.machine` variable (e.g., `personal-mac`,
`work-mac`, `lab-mac`). Two gating styles coexist:

**1. Prefix-based (legacy, identity-flavored gates)** — `{{ if hasPrefix "personal" .machine }}` /
`{{ if hasPrefix "work" .machine }}`. Used for ownership/secret splits:

- **MCP work-only**: `dot_config/mcp/machine/work.json` — servers added on work machines (e.g., AWS MCP)
- **MCP personal-only**: `dot_config/mcp/machine/personal.json.tmpl` — servers added on personal machines
- **hippo (personal-only)**: `~/.config/hippo/` + the hippo `SessionStart` hook
  (`dot_claude/modify_settings.json.tmpl`) deploy only on personal-mac, the box that runs the local
  LM brain. Gated via `hasPrefix "personal"` in `.chezmoiignore` and `modify_settings.json.tmpl`.
  Formerly a `hippo` capability; collapsed to an identity gate since hippo is intrinsically personal
  (lab and work never run it, and lab/personal are unrelated machines).
- **AeroSpace workspace assignments**: `dot_config/aerospace/aerospace.toml.tmpl` — separate
  `personal` / `work` blocks for `on-window-detected` rules; service-mode keybindings for personal
  layout scripts also gated
- **`.chezmoiignore`**: gates personal-only files (e.g., `workspace-5-comms.sh`, personal env /
  shell-function profiles) out of work deploys, and work-only files (e.g.,
  `aws-config-gen/overrides.json`) out of personal deploys

**2. Capability-based (preferred for new gates)** — capabilities live in `.chezmoidata/machines.toml`
and are looked up as `(index .machines .machine).<capability>`. Adding a future machine is one new
row in that table; gate sites don't need to change.

Current capabilities (one row per machine in `machines.toml`):

- **`tiling`** — install/configure aerospace + sketchybar + borders. Off on `lab-mac` (Screen Share
  machine prefers point-and-click). Gated in `.chezmoiignore` (skips `.config/aerospace`,
  `.config/sketchybar`) and in `dot_config/homebrew/Brewfile.tmpl` (skips the WM brew block +
  `font-sketchybar-app-font`).
- **`atuin`** — deploy `~/.config/atuin/config.toml` (mode 0600 via the source's `private_`
  prefix) pointing at the self-hosted atuin server on `i9`
  (`https://logbook.snugmarina.org`). Off on work machines so corporate shells never sync history
  to the home lab. Gated in `.chezmoiignore` (skips `.config/atuin`).
- **`mcp`** — deploy the MCP master config + run the post-apply sync hook that fans out per-tool MCP
  configs (codex, opencode, cursor, copilot, …). Off on machines that don't run a constellation of
  AI dev tools. Gated in `.chezmoiignore` (skips `.config/mcp`) and in
  `.chezmoiscripts/run_after_sync-mcp.sh.tmpl` (body becomes a no-op). (github MCP moved from a
  brew formula to the `github@claude-plugins-official` plugin — a remote HTTP server — so `mcp` no
  longer gates a Brewfile entry.)
- **`skills`** — deploy `~/.config/skills/` (the skill manifest + machine overlays) and run the
  post-apply `sync-skills` hook that populates `~/.claude/skills/` from vendored (mattpocock) +
  personal skills. Off on machines that don't run Claude Code skills. Gated in `.chezmoiignore`
  (skips `.config/skills`) and in `.chezmoiscripts/run_after_sync-skills.sh.tmpl` (body becomes a
  no-op).
- **`gui`** — install GUI applications (Raycast, Ghostty, Obsidian, VS Code, 1Password, …) +
  display fonts. On for any machine with a usable display, including `lab-mac` while it's still
  being stood up via macOS Screen Share. Flip false once a machine is genuinely headless with no
  Screen Share path. CLI tools that ship as `cask` (e.g. `1password-cli`) stay outside this gate.
  Gated in `dot_config/homebrew/Brewfile.tmpl`.
- **`dev`** — machine does language / web / mobile development. Gates the dev-only language-LSP
  plugins (`swift-lsp`, `typescript-lsp`, `lua-lsp` — `pyright-lsp`/`gopls-lsp`/`rust-analyzer-lsp`
  stay enabled on every machine), the Brewfile dev-flavored block (railway CLI, dev fonts), and the
  `dot_claude/modify_settings.json.tmpl` plugin enablement (cloudflare, frontend-design, playwright,
  railway). Off on work (work has its own dev curation) and off on `lab-mac` (home server, not a dev box).
- **`aws_sso`** — deploy AWS SSO profile generator output (`~/.aws/config` from `aws_config_gen`)
  and related shell helpers. Off on machines without AWS access. Work-only today. Gated in
  `.chezmoiignore` (skips `aws-config-gen/` overrides + `.aws/`) and in any shell profile that
  sources AWS helpers.
- **`infra`** — install infrastructure / cluster-ops tooling via mise: Kubernetes (kubectl, helm,
  k9s, kustomize), corporate access (teleport-ent), ops databases (mysql, duckdb). IaC (terraform)
  and build tooling (gradle, goreleaser, pnpm) live in the global mise block now — they install on
  every machine and are not gated here. Currently work-only; `lab-mac` flips this on once homelab
  cluster-ops (k8s) actually moves there.
- **`agent_journal`** — deploy the personal Obsidian agent-journal beta: `~/.config/agent-journal/`
  config, the `agent-journal` / `agent-note` CLI wrappers in `~/.local/bin`, and the Claude
  `Stop` lifecycle hook. Personal-only until the workflow proves out in daily use. Gated in
  `.chezmoiignore` (skips `.config/agent-journal` + the two bin wrappers); the hook file ships via
  the hook allowlist regardless but stays inert without the config.
- **`agents`** — clone the personal agent-registry (`git@github.com:stevencarpenter/agents.git`) to
  `~/.local/share/agent-registry` and run its installer, which fans the canonical agents out to each
  tool's native format (Claude, Codex, opencode, Copilot). Personal-only — the registry is on the
  user's personal GitHub (SSH) and the agents are personal content. Unlike most capabilities it has
  no `.chezmoiignore` consumer (its payload is a cloned repo, not tracked source); instead it gates
  the clone in `.chezmoiexternal.toml.tmpl` and the installer in
  `.chezmoiscripts/run_after_sync-agents.sh.tmpl` (which self-gates to a no-op when off).

> No `wireguard` capability is defined. The home network uses Tailscale (which speaks WireGuard
> under the hood) for the "phone home" use case; if a future device needs a raw WG tunnel, add
> the capability then with a real consumer in tree. See `docs/networking.md`.

To add a new machine: add a `[machines.<name>]` row in `.chezmoidata/machines.toml`, set the
capabilities you want, and add the name to the prompt hint in `.chezmoi.toml.tmpl`. To add a new
capability: add the key to every row in `machines.toml` and gate the relevant templates /
`.chezmoiignore` lines on `(index .machines .machine).<capability>`.

### Key Directories

- `dot_config/mcp/` — Master MCP config + per-machine overlays (per-tool override layer wired in `sync.py`; no override files managed in-repo yet)
- `mcp_sync/` — MCP fan-out tool (uv project, Python 3.14+, no runtime deps)
- `aws_config_gen/` — AWS SSO profile generator (uv project, Python 3.14+)
- `token_auditor/` — Token usage auditor / `codax` CLI (uv project, Python 3.14+, 100% coverage gate)
- `.chezmoiscripts/` — Post-apply hooks (MCP sync, macOS setup)
- `.chezmoidata/machines.toml` — Per-machine capability table (single source of truth for gating)
- `dot_config/zsh/` — Zsh config; `encrypted_dot_env.age` holds API keys
- `private_dot_ssh/` — chezmoi-managed `~/.ssh/config`, age-encrypted (homelab / i9 access over Tailscale; personal + lab)
- `dot_config/nvim/` — Neovim config (LazyVim)
- `scripts/` — Utility scripts
- `docs/ai-tools/` — Setup guides for MCP, Copilot, etc.

### Tmux Status Bar Integration

A monitor script (`dot_config/tmux/scripts/claude-pane-monitor.sh`) runs every status-interval and
sets per-window `@claude_state` options. The everforest color palette is defined inline (no theme
plugin) so the monitor has full control over `window-status-format` and
`window-status-current-format` with stoplight colors:

- **Green** (`#a7c080`) — actively working (braille spinner in pane title)
- **Yellow** (`#dbbc7f`) — waiting for input (pane title contains ✳)

Window names show `#{pane_title}` via `automatic-rename-format`, so tabs display Claude session
names and state spinners instead of version numbers.

### Encrypted Secrets

Environment variables live in `dot_config/zsh/encrypted_dot_env.age`. To update:
1. Edit `~/.config/zsh/.env`
2. Run `chezmoi add --encrypt ~/.config/zsh/.env`
3. Verify encryption: `head -3 ~/.local/share/chezmoi/dot_config/zsh/encrypted_dot_env.age` should show
   `-----BEGIN AGE ENCRYPTED FILE-----`

## CI

GitHub Actions in `.github/workflows/`:
- `mcp-sync-ci.yml`, `aws-config-gen-ci.yml`, `token-auditor-ci.yml` — lint + test for each Python tool
- `dotfiles-hygiene-ci.yml` — repo-wide hygiene checks

## Style

- Shell scripts: `set -euo pipefail`, bash
- Python: ruff for linting and formatting, no runtime dependencies, Python 3.14+
  - 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes
  - Verbose Google-style docstrings on classes/functions with typed `Args:` / `Returns:` sections;
    include `Raises:` when relevant
- Package manager: uv (not pip/poetry)
- Tests: `test_*.py` filenames and `test_*` function names (enforced by pre-commit)
- Chezmoi sources: keep `dot_` prefixes on managed dotfiles and `encrypted_` on age-encrypted sources
- Prefer small, focused edits; keep scripts idempotent and safe to re-run

## IntelliJ MCP in this repo

The `mcp__idea__*` tools need explicit targeting — called bare they fail with "Unable to
determine the target project for the current MCP tool call" or "No argument is passed for
required parameter 'pathInProject'". When using them in this repo, always pass
`projectPath=~/.local/share/chezmoi`, a **repo-relative** `pathInProject`
(e.g. `mcp_sync/src/mcp_sync/sync.py`), and the **exact** current `oldText` for replacements.
The global `~/.claude/CLAUDE.md` covers *preferring* these tools; this note is the
repo-specific targeting that makes them resolve.

## Commits & Pull Requests

History uses Conventional Commit prefixes: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.

- Format: `type: short imperative summary` (optionally append `(#NN)` for PR/issue references)
- Keep each commit scoped to one concern
- PRs should include: purpose, key changed paths, test/lint evidence, and any config/security
  impact (especially secrets, MCP, or shell-startup behavior)
- Include screenshots only when UI/docs rendering changes need visual confirmation
- **Do not add a `Co-Authored-By` trailer, or any "generated by" / "created by" attribution
  naming an AI agent, assistant, or harness (Claude, Codex, Copilot, Gemini, etc.), to commits
  in this repo.** This overrides the harness default. Slash commands that template such a
  trailer must strip it before committing here.
