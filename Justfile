# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Immutable token-auditor release used by the explicit network sync workflow.
# Update deliberately after reviewing the corresponding upstream release.
TOKEN_AUDITOR_VERSION := `tr -d '\n' < versions/token-auditor`

# Default recipe: show available commands
default:
    @just --list

# Open and validate a Vim Golf challenge (defaults to today; challenges live in ~/projects/vim-golf).
vim-golf *DAY:
    scripts/vim-golf play {{ DAY }}

# Show progress across the Vim Golf curriculum.
vim-golf-list:
    scripts/vim-golf list

# ── Nix (build / switch) ─────────────────────────────────

# Rebuild and switch this host's nix-darwin + home-manager config.
# Host is auto-detected from LocalHostName by rebuild.sh; pass one to override.
rebuild *HOST:
    ./rebuild.sh {{ HOST }}

# Verify the running personal-mac generation and all live cutover roots.
verify-live:
    scripts/verify-live-deployment.sh

# Show a names-only plan for adopting reviewed personal env changes into 1Password.
op-adopt *FLAGS:
    home/.local/bin/op-adopt {{ FLAGS }}

# Evaluate every declared system closure without realizing it.
check:
    nix flake check --no-update-lock-file --no-build --all-systems

# Format all tracked Nix sources with the flake's canonical formatter.
nix-fmt:
    git ls-files -z '*.nix' | xargs -0 nix fmt --

# Verify that all tracked Nix sources already match the canonical formatter.
nix-fmt-check:
    git ls-files -z '*.nix' | xargs -0 nix fmt -- --check

# Run the repository-wide Nix anti-pattern linter.
nix-lint:
    statix check .

# Bump 26.05 inputs, unstable soak, and Homebrew. Never switches.
update *ARGS:
    scripts/update-inputs.sh {{ ARGS }}

# Record the current nixpkgs-unstable channel tip, then promote that exact rev
# after DAYS have elapsed (default 7). Promotion builds and prints the closure
# diff but never switches. See scripts/update-unstable.sh for the state machine.
update-unstable *DAYS:
    scripts/update-unstable.sh {{ DAYS }}

# Explicit Homebrew update/upgrade; rebuilds only install missing declarations.
brew-upgrade:
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 brew update
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 brew bundle install --upgrade

# Compare declared and installed Homebrew inventory without changing anything.
brew-audit:
    scripts/audit-homebrew.sh

# First-time provisioning on a fresh Mac (Lix, Homebrew, first switch).
bootstrap *HOST:
    ./bootstrap.sh {{ HOST }}

# ── Sync (full deploy) ───────────────────────────────────

# Switch creates symlinks; op-render supplies SSH secrets before Git side channels.
# Forward HOST to both phases so identity gates agree. An explicit argument wins
# over DOTFILES_HOST. Render in this terminal for interactive 1Password approval.

# Full deploy: switch the generation, then run every network/SSH side channel.
sync *HOST:
    ./rebuild.sh {{ HOST }}
    DOTFILES_HOST="{{ if HOST == "" { env_var_or_default("DOTFILES_HOST", "") } else { HOST } }}" TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# Side channels only, skipping the rebuild (use when the generation is current).
sync-side-channels:
    TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# ── MCP Sync ─────────────────────────────────────────────

# Lint, test, and format both Python projects.
lint:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff check $p/src $p/tests; done
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format --check $p/src $p/tests; done

test *FLAGS:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev pytest $p/tests --cov=$p --cov-report=term-missing {{ FLAGS }}; done

fmt:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format $p/src $p/tests; done

# Require exactly one deployed machine overlay. Syncing from the master alone
# would remove overlay-only servers from live configs.
mcp-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    overlays=("$HOME"/.config/mcp/machine/*.json)
    case "${#overlays[@]}" in
      0) printf 'error: machine overlay is missing\n' >&2; exit 1 ;;
      1) uv run --project mcp_sync sync-mcp-configs --machine-config "${overlays[0]}" ;;
      *) printf 'error: multiple machine overlays deployed: %s\n' "${overlays[*]}" >&2; exit 1 ;;
    esac

# Report idle Claude teammate panes across every tmux socket (kills nothing)
reap:
    uv run --project agent_reap agent-reap report

# Every tmux server and its sessions: shows why `tmux kill-server` missed one
reap-sockets:
    uv run --project agent_reap agent-reap sockets

# ssh control masters + disowned descendants (report-only)
reap-strays:
    uv run --project agent_reap agent-reap strays

# Actually reap idle teammate panes. Leads and interactive sessions are spared.
reap-kill:
    uv run --project agent_reap agent-reap reap --kill

# ── All Python projects ──────────────────────────────────

# Run all Python checks (lint + test). Nix flake checks live under `just check`.
py-check: lint test

# ── Git hooks (lefthook) ─────────────────────────────────

# Run every lefthook pre-commit job against all files, as CI does
lefthook:
    lefthook run pre-commit --all-files

# Wire .git/hooks to lefthook.yml (also done by `just sync`)
lefthook-install:
    lefthook install
