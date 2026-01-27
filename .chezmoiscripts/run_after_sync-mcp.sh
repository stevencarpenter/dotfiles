#!/usr/bin/env bash
set -euo pipefail

# Run the MCP sync script after apply
SYNC_SCRIPT="${HOME}/.local/share/chezmoi/scripts/sync-mcp-configs.py"

if [[ -f "$SYNC_SCRIPT" ]]; then
    if ! command -v uv >/dev/null 2>&1; then
        echo "Error: uv is required but not installed or not found in PATH." >&2
        exit 1
    fi
    uv run --script "$SYNC_SCRIPT"
else
    echo "Warning: MCP sync script not found: $SYNC_SCRIPT" >&2
    exit 0  # Don't fail chezmoi apply if sync script is missing
fi
