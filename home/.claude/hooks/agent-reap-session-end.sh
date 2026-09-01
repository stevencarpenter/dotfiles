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

# Claude also caps this command handler at 20 seconds in settings-base.json.
# Finish our own timeout path first so it can terminate the whole worker process
# group and write a useful log entry before Claude tears down the hook process.
# The 14s cap plus 1s input read and 1s TERM grace leaves at least four seconds
# inside Claude's 20s outer budget for startup, logging, and SIGKILL cleanup.
reap_timeout_secs="${AGENT_REAP_HOOK_TIMEOUT_SECS:-14}"
if ! [[ "${reap_timeout_secs}" =~ ^[0-9]+$ ]] || ((reap_timeout_secs > 14)); then
  reap_timeout_secs=14
fi
readonly REAP_TIMEOUT_SECS="${reap_timeout_secs}"
readonly REAP_TERM_GRACE_SECS=1

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOK_LIB="${hook_dir}/lib"

# No agent-reap (fresh machine, mid-install, or install skipped) — nothing to do.
agent_reap_bin="$(command -v agent-reap 2>/dev/null)" || exit 0

# Hook payload arrives as JSON on stdin. Read it non-blockingly: if Claude Code
# ever invokes this with no stdin, a bare `cat` would hang the session teardown.
payload=""
if read -r -t 1 -d '' payload <&0 2>/dev/null || [[ -n "$payload" ]]; then
  :
fi
[[ -n "$payload" ]] || exit 0

# Team directories are named by the session id's FIRST segment
# (session 8b5ffff0-9e14-... -> ~/.claude/teams/session-8b5ffff0), so the full
# uuid would never match. Parse with python3 rather than sed: the value is JSON
# and must be read as JSON.
session_id="$(
  printf '%s' "$payload" \
    | /usr/bin/python3 "${HOOK_LIB}/parse-session-end-payload.py" 2>/dev/null
)" || exit 0

[[ -n "$session_id" ]] || exit 0
[[ "$session_id" =~ ^[[:alnum:]]+$ ]] || exit 0

# Only act when this session actually owned a team. A solo session has no team
# directory, and passing an unknown id would be a no-op anyway — but skipping
# keeps the common case free of a subprocess.
[[ -d "${HOME}/.claude/teams/session-${session_id}" ]] || exit 0

team_dir="${HOME}/.claude/teams/session-${session_id}"

log="${HOME}/.claude/logs/agent-reap-session-end.log"
mkdir -p "${log%/*}" 2>/dev/null || true

worker_status=1
{
  printf '\n=== %s session-%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$session_id"
  # lib/run-reap-worker.py is the portable process-group watchdog macOS's
  # missing `timeout` would otherwise provide; see its docstring.
  /usr/bin/python3 "${HOOK_LIB}/run-reap-worker.py" \
    --label "agent-reap hook" \
    --timeout "$REAP_TIMEOUT_SECS" \
    --grace "$REAP_TERM_GRACE_SECS" \
    -- "$agent_reap_bin" reap --team "$session_id" --kill
  worker_status=$?
} >>"$log" 2>&1 || true

# SessionEnd is the only path allowed to remove team state. The directory name
# was derived from a validated leading session-id segment, and the exact target
# is captured before this destructive cleanup. Only a successful reap removes
# it. SubagentStop must leave the live team's state intact for its siblings and
# parent session.
if (( worker_status == 0 )); then
  rm -rf -- "${team_dir}" 2>/dev/null || true
fi

exit 0
