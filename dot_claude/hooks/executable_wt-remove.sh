#!/usr/bin/env bash
# Claude Code WorktreeRemove hook — routes cleanup through wt.
# Reads JSON {worktree_path} from stdin.
# Best-effort: failures are logged but do not propagate (per docs, this hook
# cannot block).
set -euo pipefail

payload="$(cat)"
worktree_path=$(printf '%s' "$payload" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('worktree_path',''))" 2>/dev/null \
  || true)

[ -z "$worktree_path" ] && exit 0
[ -d "$worktree_path" ] || exit 0

(
  cd "$worktree_path" \
    && wt remove --foreground --force --no-hooks --yes
) || true
