#!/usr/bin/env bash
# Exercise skill CLI contracts without writing deployed configs or launching a browser.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

expect_status() {
  local expected="$1" actual=0
  shift
  "$@" > "$fixture/stdout" 2> "$fixture/stderr" || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'Expected status %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
    cat "$fixture/stdout" "$fixture/stderr" >&2
    exit 1
  fi
}

mkdir -p "$fixture/repo/secrets"
git init -q "$fixture/repo"
cd "$fixture/repo"
verify="$repo_root/.claude/skills/dotfiles-secret-authoring/scripts/verify_encrypted.sh"
expect_status 0 bash "$verify"
printf '%s\n' '-----BEGIN AGE ENCRYPTED FILE-----' > secrets/old.age
expect_status 1 bash "$verify"
rm secrets/old.age
printf 'invalid header\n' > 'unexpected source.age'
expect_status 1 bash "$verify"
rm 'unexpected source.age'
expect_status 0 bash "$verify"

targets="$repo_root/.claude/skills/mcp-sync-verify/scripts/print_target_paths.py"
expect_status 0 "$targets" --kind patch
expect_status 0 "$targets" --kind wholesale
expect_status 0 "$targets"
expect_status 0 "$targets" --kind patch --pretty
rg -q '^## Patched in place:' "$fixture/stdout"
for flag in --help -h; do expect_status 0 "$targets" "$flag"; done
for flag in --kind --unknown --pre; do expect_status 2 "$targets" "$flag"; done
expect_status 2 "$targets" --kind unknown

shoot="$repo_root/skills/personal/screenshot-bug-hunt/scripts/shoot.mjs"
expect_status 0 node "$shoot" --base=http://localhost:4321 --out "$fixture/shots" \
  --workdir "$fixture/playwright" --targets empty.json --only desktop --sitemap=/map.xml --help
expect_status 0 node "$shoot" -h
for flag in --base --out --workdir --targets --only --sitemap --unknown; do
  expect_status 2 node "$shoot" "$flag"
done
[[ ! -e "$fixture/shots" ]]

echo 'test-skill-helper-cli: OK (age rejection, CLI usage)'
