# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Immutable token-auditor release used by the explicit network sync workflow.
# Update deliberately after reviewing the corresponding upstream release.
TOKEN_AUDITOR_VERSION := `tr -d '\n' < versions/token-auditor`

# Default recipe: show available commands
default:
    @just --list

# Open and validate a dated Vim Golf challenge (defaults to today).
vim-golf *DAY:
    scripts/vim-golf-august play {{ DAY }}

# Show progress across the August Vim Golf curriculum.
vim-golf-list:
    scripts/vim-golf-august list

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
    python3 home/.local/bin/op-adopt {{ FLAGS }}

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

# Ordering is load-bearing, not incidental:
#   1. darwin-rebuild switch — writes the symlinks the rest depends on,
#      including ~/.config/op/render-manifest and the op:// templates.
#   2. op-render (inside sync-side-channels.sh, ordered first there) — needs
#      step 1's manifest, and renders the ~/.ssh/config step 3 authenticates
#      with.
#   3. remaining side channels — the agent-registry clone uses git@github.com
#      over SSH and so must follow step 2.
# An explicit HOST must reach BOTH halves: rebuild.sh takes it positionally,
# while sync-side-channels.sh re-derives the host via host-capability.sh, which
# reads $DOTFILES_HOST. Forwarding only the first would switch to one host's
# generation and then run the OTHER host's identity gates — e.g. rendering
# personal 1Password secrets on top of a work deployment. An empty HOST yields
# DOTFILES_HOST="", which host-capability.sh already treats as unset.
# Rendering deliberately does NOT run inside activation: 1Password authorizes
# the CLI by process ancestry and will not serve a `sudo darwin-rebuild` hook.
# Running it here means it inherits this terminal's approval.

# Full deploy: switch the generation, then run every network/SSH side channel.
sync *HOST:
    ./rebuild.sh {{ HOST }}
    DOTFILES_HOST="{{ HOST }}" TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# Side channels only, skipping the rebuild (use when the generation is current).
sync-side-channels:
    TOKEN_AUDITOR_VERSION="{{ TOKEN_AUDITOR_VERSION }}" scripts/sync-side-channels.sh

# ── MCP Sync ─────────────────────────────────────────────

# Lint mcp_sync
mcp-lint:
    uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
    uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests

# Test mcp_sync
mcp-test *FLAGS:
    uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing {{ FLAGS }}

# Format mcp_sync
mcp-fmt:
    uv run --project mcp_sync --group dev ruff format mcp_sync/src mcp_sync/tests

# Run mcp sync manually.
#
# The machine overlay is NOT optional. `sync-mcp-configs` with no
# --machine-config regenerates every target from the master alone, which
# DELETES the overlay-only servers (hippo, kaneo on personal) from the
# deployed configs rather than leaving them alone — a silent downgrade that
# still reports `[ok] Synced` for every path.
#
# The mcpSync activation hook in modules/home/sync-hooks.nix selects the
# overlay by `identity` at nix eval time. This recipe has no eval context, so
# it reads the single overlay dotfiles.nix deployed for this host and refuses
# to guess if it ever finds more than one.
mcp-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    overlays=("$HOME"/.config/mcp/machine/*.json)
    case "${#overlays[@]}" in
      0) uv run --project mcp_sync sync-mcp-configs ;;
      1) uv run --project mcp_sync sync-mcp-configs --machine-config "${overlays[0]}" ;;
      *) printf 'error: multiple machine overlays deployed: %s\n' "${overlays[*]}" >&2; exit 1 ;;
    esac

# ── Agent Reap ───────────────────────────────────────────

# Lint agent_reap
reap-lint:
    uv run --project agent_reap --group dev ruff check agent_reap/src agent_reap/tests
    uv run --project agent_reap --group dev ruff format --check agent_reap/src agent_reap/tests

# Test agent_reap
reap-test *FLAGS:
    uv run --project agent_reap --group dev pytest agent_reap/tests --cov=agent_reap --cov-report=term-missing {{ FLAGS }}

# Format agent_reap
reap-fmt:
    uv run --project agent_reap --group dev ruff format agent_reap/src agent_reap/tests

# Report idle Claude teammate panes across every tmux socket (kills nothing)
reap:
    uv run --project agent_reap agent-reap report

# Every tmux server and its sessions — shows why `tmux kill-server` missed one
reap-sockets:
    uv run --project agent_reap agent-reap sockets

# ssh control masters + disowned descendants (report-only)
reap-strays:
    uv run --project agent_reap agent-reap strays

# Actually reap idle teammate panes. Leads and interactive sessions are spared.
reap-kill:
    uv run --project agent_reap agent-reap reap --kill

# ── Firefox dashboard tabs ──────────────────

# Regenerate extension/dashboards.json from the provisioned Grafana JSON
dashboard-tabs:
    python3 firefox-dashboard-tabs/generate.py

# Lint the Firefox dashboard generator and its tests.
dashboard-tabs-lint:
    uv run --project firefox-dashboard-tabs --group dev ruff check firefox-dashboard-tabs/generate.py firefox-dashboard-tabs/tests
    uv run --project firefox-dashboard-tabs --group dev ruff format --check firefox-dashboard-tabs/generate.py firefox-dashboard-tabs/tests
    uv run --project firefox-dashboard-tabs --group dev mypy --strict firefox-dashboard-tabs/generate.py

# Test the Firefox dashboard generator and extension behavior.
dashboard-tabs-test:
    uv run --project firefox-dashboard-tabs --group dev pytest firefox-dashboard-tabs/tests
    node --test firefox-dashboard-tabs/tests/background.test.js

# Format the Firefox dashboard generator and its tests.
dashboard-tabs-fmt:
    uv run --project firefox-dashboard-tabs --group dev ruff format firefox-dashboard-tabs/generate.py firefox-dashboard-tabs/tests

# ── All Python projects ──────────────────────────────────

# Lint all Python projects
lint: mcp-lint reap-lint dashboard-tabs-lint

# Test all Python projects
test: mcp-test reap-test dashboard-tabs-test

# Format all Python projects
fmt: mcp-fmt reap-fmt dashboard-tabs-fmt

# Run all Python checks (lint + test). Nix flake checks live under `just check`.
py-check: lint test

# ── Pre-commit ───────────────────────────────────────────

# Run pre-commit on all files
pre-commit:
    pre-commit run --all-files
