# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Token-auditor pin, carried over from the retired .chezmoidata/tools.toml.
# A tag (e.g. "v0.1.0") pins a fixed release; "latest" tracks the default
# branch (main). Consumed by the `sync` recipe below.
TOKEN_AUDITOR_VERSION := "latest"

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

# Evaluate the flake without building (fast structural check).
check:
    nix flake check --no-build

# First-time provisioning on a fresh Mac (Lix, work-only age key, first switch).
bootstrap *HOST:
    ./bootstrap.sh {{ HOST }}

# ── Sync (network / SSH side channels) ───────────────────

# Clone/refresh the git externals and install the pinned token-auditor tool.
# These are the network+SSH steps intentionally kept OUT of `darwin-rebuild
# switch` (see docs/nix-migration.md, hooks bucket rule). Safe to re-run.
sync:
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

# ── AWS Config Gen ───────────────────────────────────────

# Lint aws_config_gen
aws-lint:
    uv run --project aws_config_gen --group dev ruff check aws_config_gen/src aws_config_gen/tests
    uv run --project aws_config_gen --group dev ruff format --check aws_config_gen/src aws_config_gen/tests

# Test aws_config_gen
aws-test *FLAGS:
    uv run --project aws_config_gen --group dev pytest aws_config_gen/tests --cov=aws_config_gen --cov-report=term-missing {{ FLAGS }}

# Format aws_config_gen
aws-fmt:
    uv run --project aws_config_gen --group dev ruff format aws_config_gen/src aws_config_gen/tests

# Run aws config gen (dry-run)
aws-gen:
    uv run --project aws_config_gen aws-config-gen --dry-run

# ── All Python projects ──────────────────────────────────

# Lint all Python projects
lint: mcp-lint aws-lint

# Test all Python projects
test: mcp-test aws-test

# Format all Python projects
fmt: mcp-fmt aws-fmt

# Run all Python checks (lint + test). Nix flake checks live under `just check`.
py-check: lint test

# ── Pre-commit ───────────────────────────────────────────

# Run pre-commit on all files
pre-commit:
    pre-commit run --all-files
