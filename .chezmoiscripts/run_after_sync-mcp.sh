#!/usr/bin/env bash
set -euo pipefail

# Run the MCP sync script after apply
SYNC_SCRIPT="${HOME}/.local/share/chezmoi/scripts/sync-mcp-configs.sh"

if [[ -x "$SYNC_SCRIPT" ]]; then
    "$SYNC_SCRIPT"
else
    echo "Warning: MCP sync script not found or not executable: $SYNC_SCRIPT" >&2
    exit 0  # Don't fail chezmoi apply if sync script is missing
fi
