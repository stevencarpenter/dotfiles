#!/usr/bin/env bash

# Volume — mute/unmute icon only (Material Design)
# 󰕾 nf-md-volume_high | 󰖁 nf-md-volume_off

set -euo pipefail

ORANGE=0xffe69875
GRAY=0xff7a8478

MUTED="$(osascript -e 'output muted of (get volume settings)')"

if [ "$MUTED" = "true" ]; then
  sketchybar --set "$NAME" icon=󰖁 icon.color=$GRAY
else
  sketchybar --set "$NAME" icon=󰕾 icon.color=$ORANGE
fi
