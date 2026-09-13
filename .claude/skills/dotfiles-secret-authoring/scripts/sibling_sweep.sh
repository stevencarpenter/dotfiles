#!/usr/bin/env bash
# Find every occurrence of a string in code and docs, including hidden and
# gitignored files. Exits non-zero if any match remains.
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
echo "Remove EVERY occurrence above (code AND docs) before committing: 'no secrets even if trivial'."
exit 1
