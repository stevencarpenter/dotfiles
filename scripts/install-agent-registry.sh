#!/usr/bin/env bash
# Install the personal agent registry and validate its generated Claude agents.
set -euo pipefail

uv_bin="${UV_BIN:-uv}"
project="${1:-$HOME/.local/share/agent-registry}"

if [ ! -f "$project/pyproject.toml" ]; then
  echo "error: agent registry is missing at $project; run scripts/sync-side-channels.sh first" >&2
  exit 1
fi

if ! command -v "$uv_bin" >/dev/null 2>&1; then
  echo "error: uv is required to install the agent registry" >&2
  exit 1
fi

echo "==> Installing agents from $project"
"$uv_bin" run --directory "$project" python -m agent_registry.cli install

# Refresh the SessionStart routing cache atomically after a successful install.
routing_script="$project/tools/routing/generate_context.py"
routing_cache="$HOME/.cache/agent-routing/context.md"
if [ -f "$routing_script" ]; then
  mkdir -p "$(dirname "$routing_cache")"
  routing_tmp="${routing_cache}.tmp.$$"
  trap 'rm -f "$routing_tmp"' EXIT
  "$uv_bin" run --directory "$project" python "$routing_script" >"$routing_tmp"
  mv "$routing_tmp" "$routing_cache"
  trap - EXIT
fi

# A built-in-only tools allowlist silently strips configured MCP and skill
# access. Treat that as a failed sync instead of leaving a degraded install.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$uv_bin" run --script "$script_dir/check-agent-tools-allowlist.py" "$HOME/.claude/agents"
