#!/usr/bin/env bash
set -euo pipefail

# Wrapper for the Python sync script.
exec uv run --script "${HOME}/.local/share/chezmoi/scripts/sync-mcp-configs.py"
