#!/usr/bin/env bash
# verify_encrypted.sh — assert every agenix source is real age ciphertext.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fail=0
found=0

while IFS= read -r f; do
  found=1
  if ! head -1 "$f" | grep -q -- '-----BEGIN AGE ENCRYPTED FILE-----'; then
    printf 'PLAINTEXT? %s\n' "$f"
    fail=1
  fi
done < <(find "$root/secrets" -type f -name '*.age' -not -path '*/.git/*')

if [ "$found" -eq 0 ]; then
  echo "No .age sources found under $root/secrets."
elif [ "$fail" -eq 0 ]; then
  echo "OK: all secrets/*.age sources begin with the AGE header."
fi
exit "$fail"
