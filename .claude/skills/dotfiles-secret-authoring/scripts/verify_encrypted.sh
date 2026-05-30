#!/usr/bin/env bash
# verify_encrypted.sh — assert every encrypted_*-prefixed chezmoi source is real age
# ciphertext (begins with the AGE header). Catches a sensitive file accidentally tracked
# as plaintext. Exits non-zero if any encrypted_* source is not ciphertext.
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
done < <(find "$root" -type f -name 'encrypted_*' -not -path '*/.git/*')

if [ "$found" -eq 0 ]; then
  echo "No encrypted_* sources found under $root."
elif [ "$fail" -eq 0 ]; then
  echo "OK: all encrypted_* sources begin with the AGE header."
fi
exit "$fail"
