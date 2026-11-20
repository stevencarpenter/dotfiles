#!/usr/bin/env bash
# Claude Code SessionStart hook: print the cached agent-routing context block.
#
# Agent sync generates the cache. A missing cache is valid before the first sync
# or when the agents capability is disabled.
set -euo pipefail

# The agents registry manifest can turn this hook off without removing its source.
# The key matches the [hooks] table in ~/projects/agents/sync-manifest.toml.
manifest="${SYNC_MANIFEST:-$HOME/projects/agents/sync-manifest.toml}"
if [[ -r $manifest ]] && awk -v key='"session-routing"' '
  BEGIN { pattern = key "[ \t]*=[ \t]*false" }
  /^\[/ { if (section == "hooks" && text ~ pattern) found = 1; section = $0; gsub(/[][]/, "", section); text = ""; next }
  section == "hooks" { text = text "\n" $0 }
  END { if (section == "hooks" && text ~ pattern) found = 1; exit !found }
' "$manifest"; then
  exit 0
fi
# A per-machine overlay can turn the hook off too. The identity module links
# exactly one skills overlay, so its stem names this host; DFM_IDENTITY wins.
identity="${DFM_IDENTITY:-}"
if [[ -z $identity ]]; then
  matches=0
  for f in "$HOME"/.config/skills/machine/*.json; do
    [[ -e $f ]] || continue
    matches=$((matches + 1))
    identity="$(basename "$f" .json)"
  done
  [[ $matches -eq 1 ]] || identity=""
fi
if [[ -n $identity ]]; then
  overlay="$HOME/.config/agents/machine/$identity.json"
  if [[ -r $overlay ]] && grep -Eq '"session-routing"[[:space:]]*:[[:space:]]*false' "$overlay"; then
    exit 0
  fi
fi

CACHE="${CLAUDE_ROUTING_CACHE:-$HOME/.cache/agent-routing/context.md}"

if [[ -r "$CACHE" ]]; then
  cat "$CACHE"
fi
exit 0
