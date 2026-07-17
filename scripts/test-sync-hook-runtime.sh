#!/usr/bin/env bash
# Prove the vendored activation entry points run directly from source without
# consulting a checkout-bound uv editable environment.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
python_bin="${PYTHON_BIN:-python3}"

PYTHONNOUSERSITE=1 PYTHONPATH="$repo_root/mcp_sync/src" \
  "$python_bin" -m mcp_sync --help >/dev/null
PYTHONNOUSERSITE=1 PYTHONPATH="$repo_root/mcp_sync/src" \
  "$python_bin" -m mcp_sync.skills_cli --help >/dev/null
PYTHONNOUSERSITE=1 PYTHONPATH="$repo_root/aws_config_gen/src" \
  "$python_bin" -m aws_config_gen --help >/dev/null

echo "all direct sync-hook entry points passed"
