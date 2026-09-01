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
set -uo pipefail

# Claude caps this command handler at 20 seconds in settings-base.json. The
# internal limit leaves room for the input read, logging, and TERM grace period.
reap_timeout_secs="${AGENT_REAP_HOOK_TIMEOUT_SECS:-14}"
if ! [[ "${reap_timeout_secs}" =~ ^[0-9]+$ ]] || ((reap_timeout_secs > 14)); then
  reap_timeout_secs=14
fi
readonly REAP_TIMEOUT_SECS="${reap_timeout_secs}"
readonly REAP_TERM_GRACE_SECS=1

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
  printf '%s' "$payload" | /usr/bin/python3 -c '
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

event = data.get("hook_event_name")
if event not in (None, "", "SubagentStop"):
    sys.exit(0)

agent_id = data.get("agent_id")
if not isinstance(agent_id, str):
    sys.exit(0)
agent_name, marker, agent_session = agent_id.partition("@session-")
if not marker or not agent_name or not agent_session:
    sys.exit(0)

parent = data.get("parent_session_id") or data.get("team_name")
if not isinstance(parent, str) or not parent:
    sys.exit(0)
if parent.startswith("session-"):
    parent = parent.removeprefix("session-")
session = parent.split("-", 1)[0]
agent_session = agent_session.split("-", 1)[0]
if agent_session != session:
    sys.exit(0)
if not re.fullmatch(r"[A-Za-z0-9]+", session):
    sys.exit(0)
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", agent_name):
    sys.exit(0)
print(f"{session}\t{agent_name}")
'
)" || exit 0

IFS=$'\t' read -r session_id agent_name <<<"${event_target}"
[[ -n "${session_id}" && -n "${agent_name}" ]] || exit 0
[[ -d "${HOME}/.claude/teams/session-${session_id}" ]] || exit 0

log="${HOME}/.claude/logs/agent-reap-subagent-stop.log"
mkdir -p "${log%/*}" 2>/dev/null || true

{
  printf '\n=== %s session-%s agent-%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$session_id" "$agent_name"
  AGENT_REAP_BIN="$agent_reap_bin" \
    AGENT_REAP_SESSION_ID="$session_id" \
    AGENT_REAP_AGENT_NAME="$agent_name" \
    AGENT_REAP_TIMEOUT_SECS="$REAP_TIMEOUT_SECS" \
    AGENT_REAP_TERM_GRACE_SECS="$REAP_TERM_GRACE_SECS" \
    /usr/bin/python3 - <<'PY'
import os
import signal
import subprocess
import sys

command = [
    os.environ["AGENT_REAP_BIN"],
    "reap",
    "--live-team",
    os.environ["AGENT_REAP_SESSION_ID"],
    "--completed-agent",
    os.environ["AGENT_REAP_AGENT_NAME"],
    "--kill",
]
timeout = int(os.environ["AGENT_REAP_TIMEOUT_SECS"])
grace = int(os.environ["AGENT_REAP_TERM_GRACE_SECS"])

try:
    process = subprocess.Popen(command, start_new_session=True)
    status = process.wait(timeout=timeout)
except subprocess.TimeoutExpired:
    print(f"agent-reap SubagentStop hook: timed out after {timeout}s; terminating worker group")
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        status = process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        status = process.wait()
except Exception as error:
    print(f"agent-reap SubagentStop hook: could not run worker: {error}")
    status = 1

sys.exit(status)
PY
} >>"$log" 2>&1 || true

exit 0
