#!/usr/bin/env bash
# Restart the tiling stack (replaces home.activation.startTilingStack in modules/home/tiling.nix).
# Usage: tiling-reload.sh [--check]
#   --check  Report whether the sketchybar service and AeroSpace run; exit 1 if either does not.
#   default  brew services restart sketchybar; reload AeroSpace config, or open it when not running.
#            Exit 1 when a step fails.
# borders is started by AeroSpace, so it is not managed here.
set -euo pipefail

brew=/opt/homebrew/bin/brew
sketchybar=/opt/homebrew/bin/sketchybar
aerospace_app=/Applications/AeroSpace.app/Contents/MacOS/AeroSpace
aerospace_cli=/opt/homebrew/bin/aerospace

# Read-only: is the sketchybar brew service started?
sketchybar_running() {
  "$brew" services list 2>/dev/null | awk '$1 == "sketchybar" {s = $2} END {exit !(s == "started")}'
}
aerospace_running() { /usr/bin/pgrep -x AeroSpace >/dev/null 2>&1; }

if [[ ${1:-} == --check ]]; then
  rc=0
  if sketchybar_running; then echo "ok: sketchybar service started"; else echo "not running: sketchybar service"; rc=1; fi
  if aerospace_running; then echo "ok: AeroSpace running"; else echo "not running: AeroSpace"; rc=1; fi
  exit "$rc"
elif [[ -n ${1:-} ]]; then
  echo "usage: $0 [--check]" >&2; exit 2
fi

# A failed step makes the script exit 1. A caller that must continue (just sync-dfm-apply) uses `|| echo`.
rc=0
if [[ -x $sketchybar && -x $brew ]]; then
  # Strip SUDO_* so brew services uses gui/<uid>.
  /usr/bin/env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND "$brew" services restart sketchybar || rc=1
else
  echo "tiling-reload: sketchybar not installed: skipping" >&2
fi
if [[ -x $aerospace_app ]]; then
  if aerospace_running; then "$aerospace_cli" reload-config || rc=1; else /usr/bin/open -a AeroSpace || rc=1; fi
else
  echo "tiling-reload: AeroSpace not installed: skipping" >&2
fi
[[ $rc -eq 0 ]] || echo "tiling-reload: a step failed" >&2
exit "$rc"
