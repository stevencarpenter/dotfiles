#!/usr/bin/env bash
# Apply or check the static Brewfile without upgrading anything (DFM-50).
#   brew-sync.sh           install missing items, pin sketchybar and borders, link _brew completion
#   brew-sync.sh --check   report missing items and pins; install nothing; exit non-zero on a gap
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
brewfile="$repo/Brewfile"
pinned=(sketchybar borders)

# Same policy as modules/darwin/homebrew.nix.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_UPGRADE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_UPDATE_REPORT_NEW=1
export HOMEBREW_BUNDLE_FILE="$brewfile"

mode=apply
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: ${0##*/} [--check]" >&2; exit 2 ;;
esac

command -v brew >/dev/null 2>&1 || { echo "error: brew not found" >&2; exit 1; }

if [ "$mode" = check ]; then
  status=0
  brew bundle check --file "$brewfile" --verbose || status=1
  current_pins="$(brew list --pinned)"
  echo "pinned: $(echo "$current_pins" | tr '\n' ' ')"
  for f in "${pinned[@]}"; do
    echo "$current_pins" | grep -qx "$f" || { echo "missing pin: $f" >&2; status=1; }
  done
  exit "$status"
fi

brew bundle --file "$brewfile" --no-upgrade

# `brew pin` on an already pinned formula only warns; skip those.
current_pins="$(brew list --pinned)"
for f in "${pinned[@]}"; do
  echo "$current_pins" | grep -qx "$f" || brew pin "$f"
done

# Restore brew's zsh completion link when source and directory exist.
src="$(brew --prefix)/completions/zsh/_brew"
dir="$(brew --prefix)/share/zsh/site-functions"
if [ -e "$src" ] && [ -d "$dir" ]; then
  ln -sfn "$src" "$dir/_brew"
fi
