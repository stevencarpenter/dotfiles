#!/usr/bin/env bash
# Claude Code SessionStart hook: print the cached agent-routing context block.
#
# Agent sync generates the cache. A missing cache is valid before the first sync
# or when the agents capability is disabled.
set -euo pipefail

CACHE="${CLAUDE_ROUTING_CACHE:-$HOME/.cache/agent-routing/context.md}"

if [[ -r "$CACHE" ]]; then
  cat "$CACHE"
fi
exit 0
