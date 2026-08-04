# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Immutable token-auditor release used by the explicit network sync workflow.
# Update deliberately after reviewing the corresponding upstream release.
TOKEN_AUDITOR_VERSION := `tr -d '\n' < versions/token-auditor`

# Default recipe: show available commands
default:
    @just --list

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
    nix flake check --no-build --all-systems

# Format all tracked Nix sources with the flake's canonical formatter.
nix-fmt:
    git ls-files -z '*.nix' | xargs -0 nix fmt --

# Verify that all tracked Nix sources already match the canonical formatter.
nix-fmt-check:
    git ls-files -z '*.nix' | xargs -0 nix fmt -- --check

# Run the repository-wide Nix anti-pattern linter.
nix-lint:
    statix check .

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

# Run mcp sync manually
mcp-sync:
    uv run --project mcp_sync sync-mcp-configs

# ── All Python projects ──────────────────────────────────

# Lint all Python projects
lint: mcp-lint

# Test all Python projects
test: mcp-test

# Format all Python projects
fmt: mcp-fmt

# Run all Python checks (lint + test). Nix flake checks live under `just check`.
py-check: lint test

# ── Pre-commit ───────────────────────────────────────────

# Run pre-commit on all files
pre-commit:
    pre-commit run --all-files
