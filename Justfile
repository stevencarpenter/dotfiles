# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Default recipe: show available commands
[private]
default:
    @just --list

# ── Setup and maintenance ────────────────────────────────

# Show a names-only plan for adopting reviewed personal env changes into 1Password.
[group('Targeted maintenance')]
op-adopt *FLAGS:
    home/.local/bin/op-adopt {{ FLAGS }}

# Homebrew only: refresh metadata and upgrade installed unpinned packages; accepts --dry-run.
[group('Targeted maintenance')]
brew-upgrade *ARGS:
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 brew update
    HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade {{ ARGS }}

# Compare declared and installed Homebrew inventory without changing anything.
[group('Validation')]
brew-audit:
    scripts/audit-homebrew.sh

# First-time provisioning on a fresh Mac (Command Line Tools, Homebrew, Brewfile).
[group('Setup')]
bootstrap *HOST:
    ./bootstrap.sh {{ HOST }}

# ── dfm updater hook ─────────────────────────────────────

# dfm sync's side-channels updater runs this recipe; dfm fixes its name. Not an entry point: run dfm sync.
[private]
sync-side-channels:
    scripts/sync-side-channels.sh

# ── Python checks ────────────────────────────────────────

# Lint and verify formatting in both Python projects; included in py-check.
[group('Validation')]
lint:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff check $p/src $p/tests || exit $?; done
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format --check $p/src $p/tests || exit $?; done

# Test both Python projects; included in py-check.
[group('Validation')]
test *FLAGS:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev pytest $p/tests --cov=$p --cov-report=term-missing {{ FLAGS }} || exit $?; done

# Format both Python projects (writes files).
[group('Validation')]
fmt:
    for p in mcp_sync agent_reap; do uv run --project $p --group dev ruff format $p/src $p/tests || exit $?; done

# A/B hippo enrichment models on recorded requests: record, inspect, run, report.
[group('Targeted maintenance')]
hippo-eval *ARGS:
    scripts/hippo-model-eval.py {{ ARGS }}

# Unattended model x temperature x thinking experiment: plan, start, status, stop, resume, report.
[group('Targeted maintenance')]
hippo-experiment *ARGS:
    scripts/hippo-model-experiment.py {{ ARGS }}

# Read-only hippo.db probe for the 8-bit vs 4-bit effectiveness study (Phase 0).
[group('Targeted maintenance')]
hippo-study-probe *ARGS:
    scripts/hippo-study-probe.py {{ ARGS }}

# MCP configs only; dfm sync also regenerates them (side-channels updater, through hooks-sync.sh).
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

# Run all Python checks (lint + test).
[group('Validation')]
py-check: lint test

# ── Git hooks (lefthook) ─────────────────────────────────

# Run every lefthook pre-commit job against all files, as CI does
[group('Validation')]
lefthook:
    lefthook run pre-commit --all-files

# Install hooks only (does not run checks); dfm sync's lefthook updater also does this.
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
