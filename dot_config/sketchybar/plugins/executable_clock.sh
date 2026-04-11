#!/bin/bash

# Clock + Calendar — local in bar, UTC in popup

# Local
TIME="$(date '+%H:%M:%S %Z')"
DATE="$(date '+%A, %B %d, %Y')"

# UTC
UTC_TIME="$(TZ=UTC date '+%H:%M:%S UTC')"
UTC_DATE="$(TZ=UTC date '+%A, %B %d, %Y')"

# Update bar
sketchybar --set clock label="${TIME}"
sketchybar --set calendar label="${DATE}"

# Update popup
sketchybar --set calendar.utc_date label="${UTC_DATE}"
sketchybar --set calendar.utc_time label="${UTC_TIME}"

# Hover events — both clock and calendar trigger calendar's popup
case "$SENDER" in
  mouse.entered)
    sketchybar --set calendar popup.drawing=on
    ;;
  mouse.exited)
    sketchybar --set calendar popup.drawing=off
    ;;
esac
