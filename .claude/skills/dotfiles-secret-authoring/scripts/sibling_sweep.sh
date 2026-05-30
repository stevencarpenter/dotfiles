#!/usr/bin/env bash
# sibling_sweep.sh — find EVERY occurrence of a credential/string across the whole repo
# (code AND docs), including chezmoi sources and gitignored files, so a doc-line duplicate
# is never left behind. Exits non-zero if any match remains.
#
# Usage: sibling_sweep.sh '<exact string or credential>'
set -euo pipefail

needle="${1:-}"
if [ -z "$needle" ]; then
  echo "usage: sibling_sweep.sh '<exact string or credential>'" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# -F: fixed string (treat the needle literally, not as a regex)
# --hidden: include dotfiles; --no-ignore: search even gitignored files; exclude .git internals
matches="$(rg -F -n --hidden --no-ignore --glob '!.git/**' -- "$needle" "$root" || true)"

if [ -z "$matches" ]; then
  printf "CLEAN: '%s' not found anywhere in %s\n" "$needle" "$root"
  exit 0
fi

printf "FOUND '%s' in:\n" "$needle"
printf '%s\n' "$matches"
echo
echo "Remove EVERY occurrence above (code AND docs) before committing — 'no secrets even if trivial'."
exit 1
