#!/usr/bin/env bash
# Load the real tmux config into an isolated server and assert effective cwd,
# pane-classification, and SessionEnd cleanup behavior. Text-only checks miss
# later overrides and cannot expose socket or process leaks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/dotfiles-tmux-lifecycle.XXXXXX)"
socket_path="${test_root}/tmux.sock"
server_started=0

cleanup() {
	if [[ "${server_started}" -eq 1 ]]; then
		if ! tmux -S "${socket_path}" kill-server >/dev/null 2>&1; then
			echo "tmux lifecycle cleanup: could not stop ${socket_path}; leaving socket reachable" >&2
			return
		fi
		server_started=0
	fi
	# tmux normally unlinks an explicit socket when the server exits, but remove
	# this exact test socket as well so a failed config load cannot leak it.
	rm -f -- "${socket_path}"
	rm -rf -- "${test_root}"
}
trap cleanup EXIT

XDG_CONFIG_HOME="${repo_root}/home/.config" \
		tmux -S "${socket_path}" -f "${repo_root}/home/.config/tmux/tmux.conf" \
		new-session -d -s contract -c "${repo_root}" "sleep 30"
server_started=1

# Dump the whole table once and match fields here rather than asking tmux to
# look up a single key: `list-keys -T prefix <key>` silently returns nothing on
# tmux 3.7, and `-` as a bare argument invites getopt ambiguity on any version.
prefix_table="$(tmux -S "${socket_path}" list-keys -T prefix)"

assert_binding() {
	local key="$1" expected="$2" actual
	actual="$(
		awk -v key="${key}" \
			'$1 == "bind-key" && $2 == "-T" && $3 == "prefix" && $4 == key {
				$1 = $2 = $3 = $4 = ""
				sub(/^ +/, "")
				print
			}' <<<"${prefix_table}"
	)"
	if [[ "${actual}" != *"${expected}"* ]]; then
		echo "tmux lifecycle contract: ${key} expected '${expected}', got '${actual}'" >&2
		# A missing binding usually means the config never finished loading,
		# so dump what the server actually saw.
		echo "--- tmux -V ---" >&2
		tmux -V >&2 || true
		echo "--- prefix table ---" >&2
		echo "${prefix_table}" >&2
		echo "--- server messages ---" >&2
		tmux -S "${socket_path}" show-messages -t contract >&2 || true
		exit 1
	fi
}

assert_binding c "new-window -c ${HOME}"
assert_binding '|' "split-window -h -c ${HOME}"
assert_binding - "split-window -v -c ${HOME}"

# z4h must not silently reintroduce automatic or isolated tmux startup. Keep the
# explicit value in the shell source: deleting it activates z4h's isolated
# default, while `system` replaces the outer shell with `exec tmux`.
if ! rg -Fq "zstyle ':z4h:' start-tmux no" \
	"${repo_root}/home/.config/zsh/.zshrc"; then
	echo "tmux lifecycle contract: z4h automatic tmux startup is not explicitly disabled" >&2
	exit 1
fi

# A pane title is not sufficient evidence that Claude owns the pane. Exercise
# the monitor against the isolated server with one negative control and both
# recognized state-marker forms.
create_titled_window() {
	local title="$1" window_id pane_id
	window_id="$(
		tmux -S "${socket_path}" new-window -d -P -F '#{window_id}' \
			-t contract: -c "${repo_root}" "sleep 30"
	)"
	pane_id="$(tmux -S "${socket_path}" list-panes -t "${window_id}" -F '#{pane_id}')"
	tmux -S "${socket_path}" select-pane -t "${pane_id}" -T "${title}"
	printf '%s\n' "${window_id}"
}

nvim_window="$(create_titled_window 'nvim')"
working_window="$(create_titled_window '⠴ Claude contract')"
idle_window="$(create_titled_window '✳ Claude contract')"
server_pid="$(tmux -S "${socket_path}" display-message -p '#{pid}')"

TMUX="${socket_path},${server_pid},0" CLAUDE_TEAMMATE_WARN=999 \
	"${repo_root}/home/.config/tmux/scripts/claude-pane-monitor.sh" >/dev/null

assert_window_state() {
	local window_id="$1" expected="$2" label="$3" actual
	actual="$(tmux -S "${socket_path}" show-option -wqv -t "${window_id}" @claude_state)"
	if [[ "${actual}" != "${expected}" ]]; then
		echo "tmux lifecycle contract: ${label} state expected '${expected}', got '${actual}'" >&2
		exit 1
	fi
}

assert_window_state "${nvim_window}" "" "arbitrary nvim title"
assert_window_state "${working_window}" "working" "braille working title"
assert_window_state "${idle_window}" "idle" "star waiting title"

# Claude's own command-handler timeout is the outer teardown bound. The hook's
# internal watchdog finishes first and remains effective when macOS has neither
# timeout nor gtimeout.
settings_base="${repo_root}/home/.claude/settings-base.json"
if ! jq -e '
  [.hooks.SessionEnd[]?.hooks[]?
   | select(.type == "command"
       and .command == "~/.claude/hooks/agent-reap-session-end.sh")]
  | length == 1 and .[0].timeout == 20
' "${settings_base}" >/dev/null; then
	echo "tmux lifecycle contract: SessionEnd agent-reap handler must have timeout 20" >&2
	exit 1
fi
if ! jq -e '
  [.hooks.SubagentStop[]?.hooks[]?
   | select(.type == "command"
       and .command == "~/.claude/hooks/agent-reap-subagent-stop.sh")]
  | length == 1 and .[0].timeout == 20
' "${settings_base}" >/dev/null; then
	echo "tmux lifecycle contract: SubagentStop agent-reap handler must have timeout 20" >&2
	exit 1
fi

hook_home="${test_root}/hook-home"
fake_bin="${test_root}/fake-bin"
mkdir -p "${hook_home}/.claude/teams/session-deadbeef" "${fake_bin}"
cat >"${fake_bin}/agent-reap" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"${HOME}/agent-reap-args"
printf '%s\n' "$$" >"${HOME}/agent-reap-pid"
trap 'exit 0' TERM INT
/bin/sleep 30
SH
chmod +x "${fake_bin}/agent-reap"

SECONDS=0
printf '%s\n' '{"session_id":"deadbeef-0000-0000-0000-000000000000"}' | \
	HOME="${hook_home}" \
	PATH="${fake_bin}:/usr/bin:/bin" \
	AGENT_REAP_HOOK_TIMEOUT_SECS=1 \
	"${repo_root}/home/.claude/hooks/agent-reap-session-end.sh"
hook_elapsed="${SECONDS}"

if (( hook_elapsed >= 8 )); then
	echo "tmux lifecycle contract: portable hook watchdog took ${hook_elapsed}s" >&2
	exit 1
fi
if [[ "$(<"${hook_home}/agent-reap-args")" != "reap --team deadbeef --kill" ]]; then
	echo "tmux lifecycle contract: SessionEnd hook invoked the wrong agent-reap command" >&2
	exit 1
fi
if [[ ! -d "${hook_home}/.claude/teams/session-deadbeef" ]]; then
	echo "tmux lifecycle contract: timed-out SessionEnd hook removed team state" >&2
	exit 1
fi
if ! rg -Fq 'timed out after 1s; terminating worker group' \
	"${hook_home}/.claude/logs/agent-reap-session-end.log"; then
	echo "tmux lifecycle contract: portable hook watchdog did not report its timeout" >&2
	exit 1
fi
hook_worker_pid="$(<"${hook_home}/agent-reap-pid")"
if kill -0 "${hook_worker_pid}" >/dev/null 2>&1; then
	echo "tmux lifecycle contract: timed-out agent-reap worker ${hook_worker_pid} survived" >&2
	exit 1
fi

success_bin="${test_root}/success-bin"
mkdir -p "${hook_home}/.claude/teams/session-success01" "${success_bin}"
cat >"${success_bin}/agent-reap" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"${HOME}/agent-reap-success-args"
exit 0
SH
chmod +x "${success_bin}/agent-reap"
printf '%s\n' '{"session_id":"success01-0000-0000-0000-000000000000"}' | \
	HOME="${hook_home}" \
	PATH="${success_bin}:/usr/bin:/bin" \
	"${repo_root}/home/.claude/hooks/agent-reap-session-end.sh"
if [[ "$(<"${hook_home}/agent-reap-success-args")" != "reap --team success01 --kill" ]]; then
	echo "tmux lifecycle contract: successful SessionEnd hook invoked the wrong agent-reap command" >&2
	exit 1
fi
if [[ -d "${hook_home}/.claude/teams/session-success01" ]]; then
	echo "tmux lifecycle contract: successful SessionEnd hook left team state behind" >&2
	exit 1
fi

# A reap can succeed and the removal still fail (read-only parent, busy file).
# The hook must stay best-effort and exit 0, but it must not leave "removed"
# and "silently left behind" looking identical in the log.
readonly_teams="${hook_home}/.claude/teams"
mkdir -p "${readonly_teams}/session-rofail01"
: >"${readonly_teams}/session-rofail01/marker"
chmod 500 "${readonly_teams}"
set +e
printf '%s\n' '{"session_id":"rofail01-0000-0000-0000-000000000000"}' | \
	HOME="${hook_home}" \
	PATH="${success_bin}:/usr/bin:/bin" \
	"${repo_root}/home/.claude/hooks/agent-reap-session-end.sh"
rofail_status=$?
set -e
chmod 700 "${readonly_teams}"
if (( rofail_status != 0 )); then
	echo "tmux lifecycle contract: SessionEnd hook exited ${rofail_status} when cleanup failed" >&2
	exit 1
fi
if [[ ! -d "${readonly_teams}/session-rofail01" ]]; then
	echo "tmux lifecycle contract: rm-failure case did not actually fail; test is vacuous" >&2
	exit 1
fi
if ! rg -Fq "warning: could not remove ${readonly_teams}/session-rofail01" \
	"${hook_home}/.claude/logs/agent-reap-session-end.log"; then
	echo "tmux lifecycle contract: failed team-state removal left no evidence in the log" >&2
	exit 1
fi
rm -rf -- "${readonly_teams}/session-rofail01"

mkdir -p "${hook_home}/.claude/teams/session-livecafe"
# An earlier phase already wrote this file through the same fake agent-reap;
# clear it so the poll below observes THIS invocation, not the stale one.
rm -f -- "${hook_home}/agent-reap-args"
printf '%s\n' '{"hook_event_name":"SubagentStop","agent_id":"docs-readme@session-livecafe","parent_session_id":"livecafe-0000-0000-0000-000000000000"}' | \
	HOME="${hook_home}" \
	PATH="${fake_bin}:/usr/bin:/bin" \
	AGENT_REAP_HOOK_TIMEOUT_SECS=1 \
		"${repo_root}/home/.claude/hooks/agent-reap-subagent-stop.sh"
# The SubagentStop worker is detached so it never blocks the lead's turn, so
# its evidence lands after the hook has already returned. Poll rather than
# assert immediately; a fixed sleep would either be flaky or slow.
wait_for_file() {
	local path="$1" deadline=$((SECONDS + 10))
	while ((SECONDS < deadline)); do
		[[ -s "$path" ]] && return 0
		sleep 0.1
	done
	return 1
}
if ! wait_for_file "${hook_home}/agent-reap-args"; then
	echo "tmux lifecycle contract: detached SubagentStop worker never ran" >&2
	exit 1
fi
if [[ "$(<"${hook_home}/agent-reap-args")" != "reap --live-team livecafe --completed-agent docs-readme --kill" ]]; then
	echo "tmux lifecycle contract: SubagentStop hook invoked the wrong agent-reap command" >&2
	exit 1
fi
watchdog_deadline=$((SECONDS + 10))
while ((SECONDS < watchdog_deadline)); do
	rg -Fq 'agent-reap SubagentStop hook: timed out after 1s; terminating worker group' \
		"${hook_home}/.claude/logs/agent-reap-subagent-stop.log" && break
	sleep 0.1
done
if ! rg -Fq 'agent-reap SubagentStop hook: timed out after 1s; terminating worker group' \
	"${hook_home}/.claude/logs/agent-reap-subagent-stop.log"; then
	echo "tmux lifecycle contract: SubagentStop hook watchdog did not report its timeout" >&2
	exit 1
fi

# A hook whose lib directory is missing must leave evidence, not exit silently:
# the two states are otherwise indistinguishable in the log.
missing_lib_home="${test_root}/missing-lib-home"
mkdir -p "${missing_lib_home}/.claude/teams/session-livecafe"
cp "${repo_root}/home/.claude/hooks/agent-reap-subagent-stop.sh" "${test_root}/orphan-hook.sh"
printf '%s\n' '{"hook_event_name":"SubagentStop","agent_id":"docs-readme@session-livecafe","parent_session_id":"livecafe-0000-0000-0000-000000000000"}' | \
	HOME="${missing_lib_home}" \
	PATH="${fake_bin}:/usr/bin:/bin" \
	"${test_root}/orphan-hook.sh"
if ! rg -Fq 'missing hook lib' \
	"${missing_lib_home}/.claude/logs/agent-reap-subagent-stop.log"; then
	echo "tmux lifecycle contract: hook with no lib dir failed silently" >&2
	exit 1
fi

rg -Fq '[Tmux runtime lifecycle](./tmux-runtime-lifecycle.md)' \
	"${repo_root}/docs/ai-tools/README.md"

# Stop the isolated server now, then remove the exact socket even if this tmux
# version leaves it behind. The EXIT trap repeats this cleanup on earlier errors.
if ! tmux -S "${socket_path}" kill-server >/dev/null 2>&1; then
	echo "tmux lifecycle contract: could not stop isolated server ${socket_path}" >&2
	exit 1
fi
server_started=0
rm -f -- "${socket_path}"
if [[ -e "${socket_path}" ]]; then
	echo "tmux lifecycle contract: isolated socket leaked at ${socket_path}" >&2
	exit 1
fi

echo "tmux-lifecycle-contract: cwd, explicit startup, pane state, bounded hook, and socket cleanup passed"
