#!/usr/bin/env bash
# Assert that the retired age backend has no files in the repository.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
age_source="$(find "$root" -name .git -prune -o -type f -name '*.age' -print -quit)"
if [[ -n "$age_source" ]]; then
  printf 'ERROR: age sources are not supported: %s\n' "$age_source" >&2
  exit 1
fi
echo "No .age sources found under $root."
