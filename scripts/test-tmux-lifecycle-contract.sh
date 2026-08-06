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

assert_binding() {
  local key="$1" expected="$2" actual
  actual="$(tmux -L "${socket_name}" list-keys -T prefix "${key}")"
  if [[ "${actual}" != *"${expected}"* ]]; then
    echo "tmux lifecycle contract: ${key} expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

assert_binding c "new-window -c ${HOME}"
assert_binding '|' "split-window -h -c ${HOME}"
assert_binding - "split-window -v -c ${HOME}"

rg -Fq '[Tmux runtime lifecycle](./tmux-runtime-lifecycle.md)' \
  "${repo_root}/docs/ai-tools/README.md"

echo "tmux-lifecycle-contract: effective cwd bindings and runbook link passed"
