#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_AUDITOR_DIR="${REPO_ROOT}/token_auditor"

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv is required but was not found in PATH." >&2
  exit 1
fi

cd "${TOKEN_AUDITOR_DIR}"

uv sync --locked --group dev

uv run ruff check .
uv run ruff format --check .
uv run ty check .

uv run token-auditor --help >/dev/null
uv run codax --help >/dev/null

uv run pytest -v
