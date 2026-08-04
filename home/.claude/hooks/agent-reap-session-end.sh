#!/usr/bin/env bash
# agent-reap-session-end.sh — disband a Claude Code team when its session ends.
#
# THE GAP THIS CLOSES
# Claude Code agent teams in tmux mode open one pane per teammate and never close
# them. The teammates are not orphans: they are healthy panes whose leader never
# receives EOF or SIGHUP, because nothing ever closes the pane. They therefore
# survive indefinitely, holding RAM and subagent slots. Observed: 19 idle
# teammates in one window at 7.18 GB, drained and untouched for 90 minutes.
#
# WHY --team RATHER THAN A PLAIN REAP
# `agent-reap reap` deliberately refuses to touch the caller's own team, and
# requires each teammate's inbox to be drained and stale. Both rules exist to
# protect a *live* team. At SessionEnd the team is over, so `--team <id>` scopes
# the teardown to exactly this session and skips those liveness checks. The pane
# and process-ancestry guards still hold, so this can never kill the shell it
# runs in.
#
# FAILURE POLICY
# Always exit 0. A hook that fails, hangs, or writes to stderr on a normal exit
# turns a cleanup convenience into a session-teardown bug. Every step is
# best-effort and the whole thing is bounded by a timeout.
set -uo pipefail

readonly TIMEOUT_SECS=20

# No agent-reap (fresh machine, mid-install, or install skipped) — nothing to do.
command -v agent-reap >/dev/null 2>&1 || exit 0

# Hook payload arrives as JSON on stdin. Read it non-blockingly: if Claude Code
# ever invokes this with no stdin, a bare `cat` would hang the session teardown.
payload=""
if read -r -t 2 -d '' payload <&0 2>/dev/null || [[ -n "$payload" ]]; then
  :
fi
[[ -n "$payload" ]] || exit 0

# Team directories are named by the session id's FIRST segment
# (session 8b5ffff0-9e14-... -> ~/.claude/teams/session-8b5ffff0), so the full
# uuid would never match. Parse with python3 rather than sed: the value is JSON
# and must be read as JSON.
session_id="$(
  printf '%s' "$payload" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = data.get("session_id") or ""
print(sid.split("-", 1)[0])
' 2>/dev/null
)" || exit 0

[[ -n "$session_id" ]] || exit 0

# Only act when this session actually owned a team. A solo session has no team
# directory, and passing an unknown id would be a no-op anyway — but skipping
# keeps the common case free of a subprocess.
[[ -d "${HOME}/.claude/teams/session-${session_id}" ]] || exit 0

log="${HOME}/.claude/logs/agent-reap-session-end.log"
mkdir -p "${log%/*}" 2>/dev/null || true

{
  printf '\n=== %s session-%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$session_id"
  # `timeout` is not on macOS by default; fall back to running bare rather than
  # silently skipping the cleanup.
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECS" agent-reap reap --team "$session_id" --kill 2>&1
  else
    agent-reap reap --team "$session_id" --kill 2>&1
  fi
} >>"$log" 2>&1 || true

exit 0
