#!/bin/bash

# Slack notification badge — queries macOS dock badge via lsappinfo
# No accessibility permissions required

set -euo pipefail

# Get badge label from lsappinfo
# Returns: empty (no badge), "•" (unread, count unknown), or a number
badge_label=$(lsappinfo info -only StatusLabel "Slack" 2>/dev/null | sed -E 's/.*"label"="([^"]*)".*/\1/')

case "$badge_label" in
  "" )
    # No badge
    sketchybar --set "$NAME" label="" background.drawing=off
    ;;
  "•" )
    # Unread indicator but no specific count — show generic dot
    sketchybar --set "$NAME" label="•" background.drawing=on
    ;;
  * )
    # Numeric badge count
    if [[ "$badge_label" =~ ^[0-9]+$ ]] && [ "$badge_label" -gt 0 ]; then
      if [ "$badge_label" -gt 99 ]; then
        badge_label="99+"
      fi
      sketchybar --set "$NAME" label="$badge_label" background.drawing=on
    else
      sketchybar --set "$NAME" label="" background.drawing=off
    fi
    ;;
esac
