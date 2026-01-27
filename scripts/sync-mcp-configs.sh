#!/usr/bin/env bash
set -euo pipefail

# Wrapper for the Python sync script.

# Ensure uv is available before attempting to run the sync script.
if ! command -v uv >/dev/null 2>&1; then
    echo "Error: 'uv' is not installed or not found in PATH. It is required to run sync-mcp-configs." >&2
    exit 127
fi

exec uv run --script "${HOME}/.local/share/chezmoi/scripts/sync-mcp-configs.py"
