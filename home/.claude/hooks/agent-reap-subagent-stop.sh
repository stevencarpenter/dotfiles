#!/usr/bin/env bash
# agent-reap-subagent-stop.sh: reap one completed teammate in a live team.
#
# Claude's SubagentStop payload identifies the completed agent and its parent
# team. This hook passes both identities to agent-reap, which bypasses only the
# time thresholds for that named agent. The live team's other panes remain under
# the ordinary safety rules and are not selected by this invocation.
#
# FAILURE POLICY
# Always exit 0. A cleanup hook must not turn a failed or slow reaper into a
# Claude session failure. The worker is bounded by a process-group watchdog and
# all output is written to a separate log.
#
# The worker is detached: nothing downstream reads its exit status, so running
# it synchronously would add a multi-socket tmux + process-table scan to the
# lead's critical path on every teammate completion. SessionEnd is the opposite
# case and stays synchronous, because it gates the team-directory removal.
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

log="${HOME}/.claude/logs/agent-reap-subagent-stop.log"
mkdir -p "${log%/*}" 2>/dev/null || true

# A missing lib directory means the hook was moved without its helpers, or the
# machine has not rebuilt since the link was declared. Both are indistinguishable
# from "no qualifying event" unless they leave evidence, so log before exiting.
if [[ ! -d "${HOOK_LIB}" ]]; then
  printf '%s missing hook lib: %s (run `just rebuild`)\n' \
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

# The parent session is the live team id. SubagentStop's session_id is the
# subagent's own transcript id, so prefer parent_session_id and fall back to the
# team_name/agent_id forms emitted by older Claude versions.
event_target="$(
  printf '%s' "$payload" \
    | /usr/bin/python3 "${HOOK_LIB}/parse-subagent-stop-payload.py"
)" || exit 0

IFS=$'\t' read -r session_id agent_name <<<"${event_target}"
[[ -n "${session_id}" && -n "${agent_name}" ]] || exit 0
[[ -d "${HOME}/.claude/teams/session-${session_id}" ]] || exit 0

{
  printf '\n=== %s session-%s agent-%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$session_id" "$agent_name"
  /usr/bin/python3 "${HOOK_LIB}/run-reap-worker.py" \
    --label "agent-reap SubagentStop hook" \
    --timeout "$REAP_TIMEOUT_SECS" \
    --grace "$REAP_TERM_GRACE_SECS" \
    -- "$agent_reap_bin" reap \
    --live-team "$session_id" \
    --completed-agent "$agent_name" \
    --kill
} >>"$log" 2>&1 &
disown

exit 0
