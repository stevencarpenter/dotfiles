#!/bin/bash

# Clock + Calendar — local in bar, UTC in popup
# Only update UTC popup items when popup is visible (hover)

# Local
TIME="$(date '+%H:%M:%S %Z')"
DATE="$(date '+%A, %B %d, %Y')"

# Update bar
sketchybar --set clock label="${TIME}"
sketchybar --set calendar label="${DATE}"

# Hover events — both clock and calendar trigger calendar's popup.
# UTC labels are computed lazily on enter to avoid per-tick subshells.
case "$SENDER" in
  mouse.entered)
    UTC_TIME="$(TZ=UTC date '+%H:%M:%S UTC')"
    UTC_DATE="$(TZ=UTC date '+%A, %B %d, %Y')"
    sketchybar --set calendar.utc_date label="${UTC_DATE}"
    sketchybar --set calendar.utc_time label="${UTC_TIME}"
    sketchybar --set calendar popup.drawing=on
    ;;
  mouse.exited)
    sketchybar --set calendar popup.drawing=off
    ;;
esac
