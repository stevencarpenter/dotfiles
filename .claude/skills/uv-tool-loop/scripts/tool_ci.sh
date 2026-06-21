#!/usr/bin/env bash
# tool_ci.sh — print the exact lint/type/test command sequence for whichever of the 3
# vendored uv tools a changed path belongs to. Print-only by design: the agent runs the
# block itself with the sandbox disabled (uv writes ~/.cache/uv — see sandbox-preflight).
#
# Usage: tool_ci.sh <path-under-a-tool>
set -euo pipefail

path="${1:-}"
if [ -z "$path" ]; then
  echo "usage: tool_ci.sh <path-under-mcp_sync|aws_config_gen>" >&2
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
  aws_config_gen/*|*/aws_config_gen/*|aws_config_gen)
    cat <<'EOF'
# aws_config_gen — --project form; ruff + pytest (no ty, no 100% gate)
uv run --project aws_config_gen --group dev ruff check aws_config_gen/src aws_config_gen/tests
uv run --project aws_config_gen --group dev ruff format --check aws_config_gen/src aws_config_gen/tests
uv run --project aws_config_gen --group dev pytest aws_config_gen/tests --cov=aws_config_gen --cov-report=term-missing
EOF
    ;;
  *)
    echo "ERROR: '$path' is not under mcp_sync/ or aws_config_gen/." >&2
    echo "For the mcp_sync FAN-OUT pipeline (generated configs / sandbox-HOME diff), use mcp-sync-verify instead." >&2
    exit 1
    ;;
esac

echo
echo "# NOTE: all uv calls write ~/.cache/uv — run them with dangerouslyDisableSandbox (see sandbox-preflight)."
