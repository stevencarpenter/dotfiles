#!/usr/bin/env bash
set -euo pipefail

# Run the MCP sync app after apply
SYNC_PROJECT="${HOME}/.local/share/chezmoi/mcp_sync"

if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv is required but not installed or not found in PATH." >&2
    exit 1
fi

if [[ -f "${SYNC_PROJECT}/pyproject.toml" ]]; then
    uv run --project "${SYNC_PROJECT}" sync-mcp-configs
else
    echo "Warning: MCP sync project not found: ${SYNC_PROJECT}" >&2
    exit 0  # Don't fail chezmoi apply if project is missing
fi
