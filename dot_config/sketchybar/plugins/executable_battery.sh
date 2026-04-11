#!/bin/bash

# Battery — horizontal icon + percentage + time remaining/to charge

GREEN=0xffa7c080
YELLOW=0xffdbbc7f
RED=0xffe67e80
AQUA=0xff83c092

BATT_INFO="$(pmset -g batt)"
PERCENTAGE="$(echo "$BATT_INFO" | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(echo "$BATT_INFO" | grep 'AC Power')"
TIME_LEFT="$(echo "$BATT_INFO" | grep -Eo '\d+:\d+' | head -1)"

if [ -z "$PERCENTAGE" ]; then
  exit 0
fi

# Battery icons (Material Design)
case "${PERCENTAGE}" in
  100|9[0-9]) ICON="󰁹" ;;
  8[0-9])     ICON="󰂂" ;;
  7[0-9])     ICON="󰂁" ;;
  6[0-9])     ICON="󰂀" ;;
  5[0-9])     ICON="󰁿" ;;
  4[0-9])     ICON="󰁾" ;;
  3[0-9])     ICON="󰁽" ;;
  2[0-9])     ICON="󰁼" ;;
  1[0-9])     ICON="󰁻" ;;
  *)          ICON="󰁺" ;;
esac

# Build label: percentage + time info
if [ -n "$CHARGING" ]; then
  ICON="󰂄"
  COLOR=$AQUA
  if [ -n "$TIME_LEFT" ] && [ "$TIME_LEFT" != "0:00" ]; then
    LABEL="${PERCENTAGE}% (${TIME_LEFT} to full)"
  else
    LABEL="${PERCENTAGE}%"
  fi
elif [ "$PERCENTAGE" -le 20 ]; then
  COLOR=$RED
  if [ -n "$TIME_LEFT" ]; then
    LABEL="${PERCENTAGE}% (${TIME_LEFT})"
  else
    LABEL="${PERCENTAGE}%"
  fi
elif [ "$PERCENTAGE" -le 40 ]; then
  COLOR=$YELLOW
  if [ -n "$TIME_LEFT" ]; then
    LABEL="${PERCENTAGE}% (${TIME_LEFT})"
  else
    LABEL="${PERCENTAGE}%"
  fi
else
  COLOR=$GREEN
  if [ -n "$TIME_LEFT" ]; then
    LABEL="${PERCENTAGE}% (${TIME_LEFT})"
  else
    LABEL="${PERCENTAGE}%"
  fi
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
