#!/usr/bin/env bash
# Assert that scripts/tiling-reload.sh touches nothing when the host profile does not select
# the tiling module, and stops on an unknown host. The selected path is not run here: it
# restarts real services.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# shellcheck disable=SC2016 # $1 belongs to the fake capability script
printf '#!/bin/sh\n[ "$1" = tiling ] && echo 0\n' >"$tmp/cap-off"
printf '#!/bin/sh\necho "error: cannot resolve a known host" >&2\nexit 2\n' >"$tmp/cap-unknown"
printf '#!/bin/sh\necho 1\n' >"$tmp/cap-on"
printf '#!/bin/sh\necho maybe\n' >"$tmp/cap-odd"
chmod +x "$tmp/cap-off" "$tmp/cap-unknown" "$tmp/cap-on" "$tmp/cap-odd"

out="$(HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh 2>&1)" || fail "deselected tiling must exit 0"
case "$out" in *"not selected"*) : ;; *) fail "deselected tiling must say so: $out" ;; esac

out="$(HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh --check 2>&1)" || fail "--check with deselected tiling must exit 0"
case "$out" in *"not selected"*) : ;; *) fail "--check with deselected tiling must say so: $out" ;; esac

# --check is read-only (brew services list, pgrep), so the selected path is safe to exercise.
out="$(HOST_CAPABILITY_BIN="$tmp/cap-on" scripts/tiling-reload.sh --check 2>&1)" || true
case "$out" in *"not selected"*) fail "selected tiling must not skip: $out" ;; esac
case "$out" in *sketchybar*) : ;; *) fail "selected tiling must run the checks: $out" ;; esac

rc=0; HOST_CAPABILITY_BIN="$tmp/cap-unknown" scripts/tiling-reload.sh >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "unknown host must exit 2, got $rc"
rc=0; HOST_CAPABILITY_BIN="$tmp/cap-odd" scripts/tiling-reload.sh >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "an unexpected capability answer must exit 2, got $rc"
rc=0; HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "unknown flag must exit 2, got $rc"

echo "ok: tiling-reload.sh skips a host without the tiling module, checks one with it, and stops on an unknown host"
