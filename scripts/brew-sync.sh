#!/usr/bin/env bash
# Apply or check the static Brewfile with stock Homebrew behavior (DFM-50).
#   brew-sync.sh           brew bundle --no-upgrade: install missing items, upgrade nothing, link _brew completion
#   brew-sync.sh --check   report missing items; install nothing; exit non-zero on a gap
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
brewfile="$repo/Brewfile"

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_BUNDLE_FILE="$brewfile"

mode=apply
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: ${0##*/} [--check]" >&2; exit 2 ;;
esac

command -v brew >/dev/null 2>&1 || { echo "error: brew not found" >&2; exit 1; }

if [ "$mode" = check ]; then
  exec brew bundle check --file "$brewfile" --verbose
fi

# Upgrades stay in `just update`, which previews them first; a config apply must not upgrade.
brew bundle --file "$brewfile" --no-upgrade

# Restore brew's zsh completion link when source and directory exist.
src="$(brew --prefix)/completions/zsh/_brew"
dir="$(brew --prefix)/share/zsh/site-functions"
if [ -e "$src" ] && [ -d "$dir" ]; then
  ln -sfn "$src" "$dir/_brew"
fi
