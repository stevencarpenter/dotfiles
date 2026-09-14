#!/usr/bin/env bash
# Flag test files that reference real HOME paths without an isolation fixture.
# This file-level heuristic cannot prove isolation. Review each flagged file;
# exit non-zero when any are found.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fail=0

for tool in mcp_sync; do
  testdir="$root/$tool/tests"
  [ -d "$testdir" ] || continue

  suspect_files="$(rg -l --glob '*.py' -e 'Path\.home\(\)' -e 'os\.path\.expanduser' -e '~/\.aws' -e '"/Users/' "$testdir" 2>/dev/null || true)"
  [ -z "$suspect_files" ] && continue

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    # Fixture presence in the file does not prove each HOME reference is isolated.
    if ! rg -q -e 'tmp_path' -e 'monkeypatch' -e 'tmpdir' -e 'tmp_path_factory' "$file" 2>/dev/null; then
      printf 'REVIEW %s: references real HOME/aws path with no tmp_path/monkeypatch guard\n' "$file"
      fail=1
    fi
  done <<< "$suspect_files"
done

[ "$fail" -eq 0 ] && echo "OK: no tool test references real HOME state without a tmp_path/monkeypatch guard."
exit "$fail"
