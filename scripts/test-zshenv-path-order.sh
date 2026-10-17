#!/usr/bin/env bash
# Assert that a non-interactive zsh keeps .zshrc precedence: local wrappers (gh account
# routing), mise shims, then Homebrew. `zsh -c` from GUI apps and ssh commands take this path.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zsh_bin="$(command -v zsh)"
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

# shellcheck disable=SC2016 # the zsh expression runs inside zsh
got="$(env -i HOME="$home" ZDOTDIR="$repo_root/home/.config/zsh" PATH=/usr/bin:/bin \
  "$zsh_bin" -c 'print -r -- "${(j: :)path[1,3]}"')"
want="$home/.local/bin $home/.local/share/mise/shims /opt/homebrew/bin"
if [ "$got" != "$want" ]; then
  echo "FAIL: non-interactive path starts with: $got" >&2
  echo "      want: $want" >&2
  exit 1
fi
echo "ok: non-interactive zsh keeps local wrappers, mise shims, then Homebrew"
