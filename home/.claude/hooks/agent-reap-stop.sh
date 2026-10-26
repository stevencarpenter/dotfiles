#!/usr/bin/env bash
# agent-reap-stop.sh: reap the lead's finished split-pane teammates.
#
# A split-pane (tmux) teammate is a separate Claude process. When it finishes
# a turn, no hook event reaches the lead: TeammateIdle fires for in-process
# teammates only, and the teammate's own Stop hook cannot reap its own pane
# (agent-reap protects the caller's ancestry). The lead's Stop event is the
# one lead-side moment that follows a teammate's report, so this hook runs a
# reap scoped to the lead's live team. agent-reap keeps every liveness gate
# (waiting title, sleeping process, drained inbox older than
# teammate_idle_minutes), so a teammate that just reported is left alone.
#
# FAILURE POLICY
# Always exit 0. A cleanup hook must not turn a failed or slow reaper into a
# Claude session failure. The worker is bounded by a process-group watchdog and
# all output is written to a separate log.
#
# The worker is detached: nothing downstream reads its exit status, so running
# it synchronously would add a multi-socket tmux + process-table scan to the
# lead's critical path on every turn. SessionEnd is the opposite case and stays
# synchronous, because it gates the team-directory removal.
set -uo pipefail

# Claude caps this command handler at 20 seconds in settings-base.json. The
# internal limit leaves room for the input read, logging, and TERM grace period.
reap_timeout_secs="${AGENT_REAP_HOOK_TIMEOUT_SECS:-14}"
if ! [[ "${reap_timeout_secs}" =~ ^[0-9]+$ ]] || ((reap_timeout_secs > 14)); then
  reap_timeout_secs=14
fi
readonly REAP_TIMEOUT_SECS="${reap_timeout_secs}"
readonly REAP_TERM_GRACE_SECS=1

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOK_LIB="${hook_dir}/lib"

log="${HOME}/.claude/logs/agent-reap-stop.log"
mkdir -p "${log%/*}" 2>/dev/null || true

# A missing lib directory means the hook was moved without its helpers, or the
# machine has not rebuilt since the link was declared. Both are indistinguishable
# from "no qualifying event" unless they leave evidence, so log before exiting.
if [[ ! -d "${HOOK_LIB}" ]]; then
  printf '%s missing hook lib: %s (run `just sync-dfm`)\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${HOOK_LIB}" >>"$log" 2>/dev/null || true
  exit 0
fi

agent_reap_bin="$(command -v agent-reap 2>/dev/null)" || exit 0

# A command hook can be invoked without a closed stdin. Read for at most one
# second so malformed or absent input never blocks the parent session.
payload=""
if read -r -t 1 -d '' payload <&0 2>/dev/null || [[ -n "$payload" ]]; then
  :
fi
[[ -n "$payload" ]] || exit 0

# Team directories are named by the session id's first segment; the parser
# reads the value as JSON rather than by regex.
session_id="$(
  printf '%s' "$payload" \
    | /usr/bin/python3 "${HOOK_LIB}/parse-session-end-payload.py" 2>/dev/null
)" || exit 0
[[ -n "$session_id" ]] || exit 0
[[ "$session_id" =~ ^[[:alnum:]]+$ ]] || exit 0

# Solo sessions, and split-pane teammates (whose own session id names no team
# directory), exit here without a subprocess.
[[ -d "${HOME}/.claude/teams/session-${session_id}" ]] || exit 0

{
  printf '\n=== %s session-%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$session_id"
  /usr/bin/python3 "${HOOK_LIB}/run-reap-worker.py" \
    --label "agent-reap Stop hook" \
    --timeout "$REAP_TIMEOUT_SECS" \
    --grace "$REAP_TERM_GRACE_SECS" \
    -- "$agent_reap_bin" reap --live-team "$session_id" --kill
} >>"$log" 2>&1 &
disown

exit 0
