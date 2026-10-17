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
chmod +x "$tmp/cap-off" "$tmp/cap-unknown"

out="$(HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh 2>&1)" || fail "deselected tiling must exit 0"
case "$out" in *"not selected"*) : ;; *) fail "deselected tiling must say so: $out" ;; esac

out="$(HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh --check 2>&1)" || fail "--check with deselected tiling must exit 0"
case "$out" in *"not selected"*) : ;; *) fail "--check with deselected tiling must say so: $out" ;; esac

if HOST_CAPABILITY_BIN="$tmp/cap-unknown" scripts/tiling-reload.sh >/dev/null 2>&1; then
  fail "unknown host must not exit 0"
fi
if HOST_CAPABILITY_BIN="$tmp/cap-off" scripts/tiling-reload.sh --bogus >/dev/null 2>&1; then
  fail "unknown flag must exit 2"
fi

echo "ok: tiling-reload.sh skips a host without the tiling module and stops on an unknown host"
