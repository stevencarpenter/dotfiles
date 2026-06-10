#!/bin/bash

# Slack notification badge — queries macOS dock badge via lsappinfo
# No accessibility permissions required

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/app_badge.sh"

badge_label="$(get_app_badge "Slack")"

if [ -n "$badge_label" ]; then
  sketchybar --set "$NAME" label="$badge_label" background.drawing=on
else
  sketchybar --set "$NAME" label="" background.drawing=off
fi
