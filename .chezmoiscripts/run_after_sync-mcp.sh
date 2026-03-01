#!/usr/bin/env bash
set -euo pipefail

# Run the MCP sync app after apply
SYNC_PROJECT="${HOME}/.local/share/chezmoi/mcp_sync"
STRICT_MODE="${MCP_SYNC_STRICT:-0}"

fail_or_warn() {
    local message="$1"
    if [[ "${STRICT_MODE}" == "1" ]]; then
        echo "Error: ${message}" >&2
        exit 1
    fi
    echo "Warning: ${message}" >&2
}

if ! command -v uv >/dev/null 2>&1; then
    fail_or_warn "uv is not installed or not found in PATH; skipping MCP sync. Set MCP_SYNC_STRICT=1 to fail instead."
    exit 0
fi

if [[ -f "${SYNC_PROJECT}/pyproject.toml" ]]; then
    if ! uv run --project "${SYNC_PROJECT}" sync-mcp-configs; then
        fail_or_warn "MCP sync failed for ${SYNC_PROJECT}. Set MCP_SYNC_STRICT=1 to fail instead."
        exit 0
    fi
else
    echo "Warning: MCP sync project not found: ${SYNC_PROJECT}" >&2
    exit 0  # Don't fail chezmoi apply if project is missing
fi
