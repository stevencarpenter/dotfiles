# Dotfiles task runner
# Usage: just <recipe>       List: just --list

# Default recipe: show available commands
default:
    @just --list

# ── Chezmoi ──────────────────────────────────────────────

# Preview changes that would be applied
diff:
    chezmoi diff

# Apply dotfiles
apply *FLAGS:
    chezmoi apply {{ FLAGS }}

# Apply with verbose output
apply-verbose:
    chezmoi apply -v

# ── MCP Sync ─────────────────────────────────────────────

# Lint mcp_sync
mcp-lint:
    uv run --project mcp_sync --extra dev ruff check mcp_sync/src mcp_sync/tests
    uv run --project mcp_sync --extra dev ruff format --check mcp_sync/src mcp_sync/tests

# Test mcp_sync
mcp-test *FLAGS:
    uv run --project mcp_sync --extra dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing {{ FLAGS }}

# Format mcp_sync
mcp-fmt:
    uv run --project mcp_sync --extra dev ruff format mcp_sync/src mcp_sync/tests

# Run mcp sync manually
mcp-sync:
    uv run --project mcp_sync sync-mcp-configs

# ── AWS Config Gen ───────────────────────────────────────

# Lint aws_config_gen
aws-lint:
    uv run --project aws_config_gen --extra dev ruff check aws_config_gen/src aws_config_gen/tests
    uv run --project aws_config_gen --extra dev ruff format --check aws_config_gen/src aws_config_gen/tests

# Test aws_config_gen
aws-test *FLAGS:
    uv run --project aws_config_gen --extra dev pytest aws_config_gen/tests --cov=aws_config_gen --cov-report=term-missing {{ FLAGS }}

# Format aws_config_gen
aws-fmt:
    uv run --project aws_config_gen --extra dev ruff format aws_config_gen/src aws_config_gen/tests

# Run aws config gen (dry-run)
aws-gen:
    uv run --project aws_config_gen aws-config-gen --dry-run

# ── All Projects ─────────────────────────────────────────

# Lint all Python projects
lint: mcp-lint aws-lint

# Test all Python projects
test: mcp-test aws-test

# Format all Python projects
fmt: mcp-fmt aws-fmt

# Run all checks (lint + test)
check: lint test

# ── Pre-commit ───────────────────────────────────────────

# Run pre-commit on all files
pre-commit:
    pre-commit run --all-files
