#!/usr/bin/env bash
# assert_no_home_writes.sh — authoring lint: flag tool TESTS that reference real $HOME state
# (e.g. ~/.aws/config, Path.home(), an absolute /Users/ path) without a tmp_path/monkeypatch
# guard. Catches the "tests created a real ~/.aws/config" class of damage. Heuristic, not a
# proof — REVIEW lines are candidates, not certain bugs. Exits non-zero if any are found.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fail=0

for tool in mcp_sync aws_config_gen; do
  testdir="$root/$tool/tests"
  [ -d "$testdir" ] || continue

  # Files that reference a real-HOME path pattern at all.
  suspect_files="$(rg -l --glob '*.py' -e 'Path\.home\(\)' -e 'os\.path\.expanduser' -e '~/\.aws' -e '"/Users/' "$testdir" 2>/dev/null || true)"
  [ -z "$suspect_files" ] && continue

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    # A file is OK if it ALSO uses an isolation fixture somewhere.
    if ! rg -q -e 'tmp_path' -e 'monkeypatch' -e 'tmpdir' -e 'tmp_path_factory' "$file" 2>/dev/null; then
      printf 'REVIEW %s — references real HOME/aws path with no tmp_path/monkeypatch guard\n' "$file"
      fail=1
    fi
  done <<< "$suspect_files"
done

[ "$fail" -eq 0 ] && echo "OK: no tool test references real HOME state without a tmp_path/monkeypatch guard."
exit "$fail"
