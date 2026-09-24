#!/usr/bin/env bash
# Move the Firstmate pin to upstream main. Preview by default; --apply moves the
# checkout and rewrites the tracked revision so the bump is a reviewable diff.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"
apply=0
if [ "${1:-}" = --apply ]; then
  apply=1
  shift
fi
host="${1:-}"

if [ "$("$capability_bin" mcp "$host")" != 1 ]; then
  echo "==> Skipping Firstmate (mcp capability disabled)"
  exit 0
fi

url=https://github.com/kunchenguid/firstmate.git
revision_file="$HOME/.config/firstmate/revision"
checkout="$HOME/.local/share/firstmate/repo"
pin="$(tr -d '\n' <"$revision_file")"

if [ -d "$checkout/.git" ]; then
  git -C "$checkout" fetch -q "$url" main
  target="$(git -C "$checkout" rev-parse FETCH_HEAD)"
else
  target="$(git ls-remote "$url" refs/heads/main | cut -f1)"
fi
if [[ ! "$target" =~ ^[0-9a-f]{40}$ ]]; then
  echo "update-firstmate: could not resolve upstream main" >&2
  exit 1
fi

if [ "$apply" -eq 0 ]; then
  echo "==> Firstmate upstream changes ($pin -> $target)"
  if [ "$pin" = "$target" ]; then
    echo "already current"
  elif [ -d "$checkout/.git" ]; then
    git -C "$checkout" log --oneline "$pin..$target" 2>/dev/null ||
      echo "pin $pin is not in the local checkout history"
  else
    echo "not installed; sync will clone $target"
  fi
  exit 0
fi

# Refuse anything that would discard work or pull the tree out from under a
# running supervisor. A checkout that drifted forward (e.g. /updatefirstmate)
# is fine as long as upstream main still contains it.
if [ -d "$checkout/.git" ]; then
  if [ -n "$(git -C "$checkout" status --porcelain)" ]; then
    echo "update-firstmate: $checkout has local changes; inspect it first" >&2
    exit 1
  fi
  if ! git -C "$checkout" merge-base --is-ancestor HEAD "$target"; then
    echo "update-firstmate: $checkout HEAD is not on upstream main; inspect it first" >&2
    exit 1
  fi
  if lsof -d cwd -Fn 2>/dev/null | rg -Fxq "n$checkout"; then
    echo "update-firstmate: Firstmate is running; stop it and its workers, then rerun" >&2
    exit 1
  fi
  git -C "$checkout" checkout -q --detach "$target"
fi
printf '%s\n' "$target" >"$revision_file"
echo "==> Firstmate pinned to $target"
