#!/usr/bin/env bash
# Claude Code WorktreeCreate hook — delegates to Worktrunk.
# Reads JSON {worktree_path?, base_branch?} from stdin (Claude Code payload).
# Writes the wt-created worktree path to stdout (Claude Code uses this).
# Any non-zero exit aborts worktree creation in Claude Code.
set -euo pipefail

payload="$(cat)"

# Derive a unique suffix. If Claude proposed a path, reuse its tail; otherwise
# fall back to timestamp + PID for uniqueness across concurrent subagents.
proposed=$(printf '%s' "$payload" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('worktree_path',''))" 2>/dev/null \
  || true)
suffix="$(basename "${proposed:-}")"
suffix="${suffix#worktree-}"
[ -z "$suffix" ] && suffix="$(date +%s)-$$"

branch="claude/${suffix}"

# Delegate to wt. --format=json is documented as designed for this hook.
# Output schema (verified 2026-05-08):
#   {"action":"created","branch":"...","path":"...","created_branch":true,"base_branch":"main"}
result="$(wt switch --create --no-cd --yes --format=json "$branch")"
printf '%s' "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['path'])"
