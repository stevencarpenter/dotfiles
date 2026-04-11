#!/bin/bash

# Battery indicator — shows percentage and appropriate icon

GREEN=0xffa7c080
YELLOW=0xffdbbc7f
RED=0xffe67e80

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ -z "$PERCENTAGE" ]; then
  exit 0
fi

case "${PERCENTAGE}" in
  100|9[0-9]) ICON="󰁹"; COLOR=$GREEN ;;
  8[0-9])     ICON="󰂂"; COLOR=$GREEN ;;
  7[0-9])     ICON="󰂁"; COLOR=$GREEN ;;
  6[0-9])     ICON="󰂀"; COLOR=$GREEN ;;
  5[0-9])     ICON="󰁿"; COLOR=$GREEN ;;
  4[0-9])     ICON="󰁾"; COLOR=$YELLOW ;;
  3[0-9])     ICON="󰁽"; COLOR=$YELLOW ;;
  2[0-9])     ICON="󰁼"; COLOR=$YELLOW ;;
  1[0-9])     ICON="󰁻"; COLOR=$RED ;;
  *)          ICON="󰁺"; COLOR=$RED ;;
esac

if [ -n "$CHARGING" ]; then
  ICON="󰂄"
  COLOR=$GREEN
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="${PERCENTAGE}%"
