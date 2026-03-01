#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MCP_SYNC_DIR="${REPO_ROOT}/mcp_sync"

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv is required but was not found in PATH." >&2
  exit 1
fi

cd "${MCP_SYNC_DIR}"

uv run --extra dev ruff check --fix src tests
uv run --extra dev ruff format --check src tests
uv run --extra dev pytest --cov=mcp_sync --cov-report=term-missing
