#!/usr/bin/env bash
# Claude Code WorktreeRemove hook — routes cleanup through wt.
# Reads JSON {worktree_path} from stdin.
# Best-effort: failures are silently swallowed (per docs, this hook cannot block).
set -euo pipefail

command -v wt >/dev/null 2>&1 || { echo "wt-remove.sh: wt not on PATH; cleanup skipped" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "wt-remove.sh: jq not on PATH; cleanup skipped" >&2; exit 0; }

worktree_path=$(jq -r '.worktree_path // ""' 2>/dev/null || true)

[ -z "$worktree_path" ] && exit 0
[ -d "$worktree_path" ] || exit 0

# Capture branch + primary repo BEFORE the directory is destroyed, so we can
# call `wt remove` from a stable cwd. Running from inside the worktree leaves
# the shell with a dangling cwd once wt deletes the directory.
branch=$(git -C "$worktree_path" symbolic-ref --short HEAD 2>/dev/null || true)
primary_repo=$(git -C "$worktree_path" worktree list --porcelain 2>/dev/null \
  | awk '/^worktree / {print $2; exit}')

# Best-effort contract: bail quietly if we can't derive the pieces we need.
[ -n "$branch" ] || exit 0
[ -n "$primary_repo" ] || exit 0
# Refuse to remove the primary worktree itself.
[ "$primary_repo" != "$worktree_path" ] || exit 0

(
  cd "$primary_repo" \
    && wt remove --foreground --force --no-hooks --yes "$branch"
) || true
