#!/usr/bin/env bash
# Claude Code SessionStart hook: print the cached agent-routing context block.
#
# Generation is NOT done per-session. The routing block only changes when
# the agents repo or lib/machines.nix changes — both are rebuild-time
# events, not session-start-time events. The cache is written by a step
# appended to run_after_sync-agents.sh.tmpl (right after it fans agents out
# to ~/.claude/agents), so this hook just cats a static file: sub-millisecond,
# no Python startup cost, no staleness risk introduced by the hook itself.
#
# If the cache is missing (never synced, or agents capability off), emit
# nothing — silence is correct here, not an error: a SessionStart hook with
# no useful output should not spend any context or print noise.
set -euo pipefail

CACHE="${CLAUDE_ROUTING_CACHE:-$HOME/.cache/agent-routing/context.md}"

if [[ -r "$CACHE" ]]; then
  cat "$CACHE"
fi
exit 0
