# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Immutable token-auditor release used by the explicit network sync workflow.
# Update deliberately after reviewing the corresponding upstream release.
TOKEN_AUDITOR_VERSION := `tr -d '\n' < versions/token-auditor`

# Default recipe: show available commands
[private]
default:
    @just --list

# Open and validate a Vim Golf challenge (defaults to today; challenges live in ~/projects/vim-golf).
[group('Utilities')]
vim-golf *DAY:
    scripts/vim-golf play {{ DAY }}

# Show progress across the Vim Golf curriculum.
[group('Utilities')]
vim-golf-list:
    scripts/vim-golf list

# ── Nix (build / switch) ─────────────────────────────────

# Apply Nix configuration only; included in sync and update. Optional HOST override.
[group('Daily')]
rebuild *HOST:
    ./rebuild.sh {{ HOST }}

# Verify the running personal-mac generation and all live cutover roots.
[group('Validation')]
verify-live:
    scripts/verify-live-deployment.sh

# Show a names-only plan for adopting reviewed personal env changes into 1Password.
[group('Targeted maintenance')]
op-adopt *FLAGS:
    home/.local/bin/op-adopt {{ FLAGS }}

# Evaluate every declared system closure without realizing it.
[group('Validation')]
check:
    nix flake check --no-update-lock-file --no-build --all-systems

# Format all tracked Nix sources with the flake's canonical formatter.
[group('Validation')]
nix-fmt:
    git ls-files -z '*.nix' | xargs -0 nix fmt --

# Verify that all tracked Nix sources already match the canonical formatter.
[group('Validation')]
nix-fmt-check:
    git ls-files -z '*.nix' | xargs -0 nix fmt -- --check

# Run the repository-wide Nix anti-pattern linter.
[group('Validation')]
nix-lint:
    statix check .

# Preview all rolling package updates, approve, then sync. Pass -y to approve automatically.
[group('Daily')]
update *ARGS:
    scripts/update-inputs.sh {{ ARGS }}

# Nix unstable only: soak 24 hours by default, promote/build, never switch. Included in update.
[group('Targeted maintenance')]
update-unstable *DAYS:
    scripts/update-unstable.sh {{ DAYS }}

# Homebrew only: refresh metadata and upgrade installed unpinned packages; accepts --dry-run.
[group('Targeted maintenance')]
brew-upgrade *ARGS:
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 brew update
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade {{ ARGS }}

# Compare declared and installed Homebrew inventory without changing anything.
[group('Validation')]
brew-audit:
    scripts/audit-homebrew.sh

# First-time provisioning on a fresh Mac (Lix, Homebrew, first switch).
[group('Setup')]
bootstrap *HOST:
    ./bootstrap.sh {{ HOST }}

# ── Sync (full deploy) ───────────────────────────────────

# Switch creates symlinks; op-render supplies SSH secrets before Git side channels.
# Forward HOST to both phases so identity gates agree. An explicit argument wins
# over DOTFILES_HOST. Render in this terminal for interactive 1Password approval.

# Deploy current Nix pins, then side channels (including mise upgrades). Included in update.
[group('Daily')]
sync *HOST: (rebuild HOST)
    DOTFILES_HOST="{{ if HOST == "" { env_var_or_default("DOTFILES_HOST", "") } else { HOST } }}" TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# Mise upgrades, secrets, Git sources, agents, and tools only; included in sync.
[group('Targeted maintenance')]
sync-side-channels:
    TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# Firstmate only: install the pinned distro; included in sync-side-channels when enabled.
[group('Targeted maintenance')]
firstmate-setup:
    firstmate --setup

# ── Python checks ────────────────────────────────────────

# Lint and verify formatting in both Python projects; included in py-check.
[group('Validation')]
lint:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff check $p/src $p/tests; done
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format --check $p/src $p/tests; done

# Test both Python projects; included in py-check.
[group('Validation')]
test *FLAGS:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev pytest $p/tests --cov=$p --cov-report=term-missing {{ FLAGS }}; done

# Format both Python projects (writes files).
[group('Validation')]
fmt:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format $p/src $p/tests; done

# MCP configs only; also regenerated during rebuild when enabled.
[group('Targeted maintenance')]
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
[group('Utilities')]
reap:
    uv run --project agent_reap agent-reap report

# Every tmux server and its sessions: shows why `tmux kill-server` missed one
[group('Utilities')]
reap-sockets:
    uv run --project agent_reap agent-reap sockets

# ssh control masters + disowned descendants (report-only)
[group('Utilities')]
reap-strays:
    uv run --project agent_reap agent-reap strays

# Actually reap idle teammate panes. Leads and interactive sessions are spared.
[group('Utilities')]
reap-kill:
    uv run --project agent_reap agent-reap reap --kill

# ── All Python projects ──────────────────────────────────

# Run all Python checks (lint + test). Nix flake checks live under `just check`.
[group('Validation')]
py-check: lint test

# ── Git hooks (lefthook) ─────────────────────────────────

# Run every lefthook pre-commit job against all files, as CI does
[group('Validation')]
lefthook:
    lefthook run pre-commit --all-files

# Install hooks only (does not run checks); included in sync-side-channels.
[group('Targeted maintenance')]
lefthook-install:
    lefthook install

# ── Repo atlas (derived static site) ─────────────────────

# Build the atlas into site/. Deterministic and free: no model calls.
[group('Utilities')]
site:
    ./scripts/build-site.py

# Serve the built atlas locally.
[group('Utilities')]
site-serve: site
    @echo "atlas: http://127.0.0.1:8931"
    python3 -m http.server 8931 -d site

# Fail when a cached summary is stale or a qualifying node has none. Free.
[group('Validation')]
site-check:
    ./scripts/build-site.py --check
    ./scripts/test-build-site.sh

# Print the nodes that qualify for synthesis, and why.
[group('Utilities')]
site-queue:
    ./scripts/build-site.py --queue --explain
