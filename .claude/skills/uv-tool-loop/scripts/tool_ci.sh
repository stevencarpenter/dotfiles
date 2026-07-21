#!/usr/bin/env bash
# tool_ci.sh — print the exact lint/type/test command sequence for the vendored uv tool
# (mcp_sync) a changed path belongs to. Print-only by design: the agent runs the
# block itself with the sandbox disabled (uv writes ~/.cache/uv — see sandbox-preflight).
#
# Usage: tool_ci.sh <path-under-mcp_sync>
set -euo pipefail

path="${1:-}"
if [ -z "$path" ]; then
  echo "usage: tool_ci.sh <path-under-mcp_sync>" >&2
  exit 2
fi

case "$path" in
  mcp_sync/*|*/mcp_sync/*|mcp_sync)
    cat <<'EOF'
# mcp_sync — --project form; ruff + pytest with coverage report (no ty, no 100% gate)
uv run --project mcp_sync --group dev ruff check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev ruff format --check mcp_sync/src mcp_sync/tests
uv run --project mcp_sync --group dev pytest mcp_sync/tests --cov=mcp_sync --cov-report=term-missing
EOF
    ;;
  *)
    echo "ERROR: '$path' is not under mcp_sync/." >&2
    echo "For the mcp_sync FAN-OUT pipeline (generated configs / sandbox-HOME diff), use mcp-sync-verify instead." >&2
    exit 1
    ;;
esac

echo
echo "# NOTE: all uv calls write ~/.cache/uv — run them with dangerouslyDisableSandbox (see sandbox-preflight)."
