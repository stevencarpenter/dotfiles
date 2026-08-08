#!/usr/bin/env bash
# Load the real tmux config into an isolated server and assert the effective
# cwd bindings. Text-only checks miss later duplicate binds that override the
# intended command, which is the slow regression this contract prevents.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
socket_name="dotfiles-lifecycle-${$}"

cleanup() {
	tmux -L "${socket_name}" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

XDG_CONFIG_HOME="${repo_root}/home/.config" \
	tmux -L "${socket_name}" -f "${repo_root}/home/.config/tmux/tmux.conf" \
	new-session -d -s contract -c "${repo_root}"

# Dump the whole table once and match fields here rather than asking tmux to
# look up a single key: `list-keys -T prefix <key>` silently returns nothing on
# tmux 3.7, and `-` as a bare argument invites getopt ambiguity on any version.
prefix_table="$(tmux -L "${socket_name}" list-keys -T prefix)"

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
		tmux -L "${socket_name}" show-messages -t contract >&2 || true
		exit 1
	fi
}

assert_binding c "new-window -c ${HOME}"
assert_binding '|' "split-window -h -c ${HOME}"
assert_binding - "split-window -v -c ${HOME}"

rg -Fq '[Tmux runtime lifecycle](./tmux-runtime-lifecycle.md)' \
	"${repo_root}/docs/ai-tools/README.md"

echo "tmux-lifecycle-contract: effective cwd bindings and runbook link passed"
