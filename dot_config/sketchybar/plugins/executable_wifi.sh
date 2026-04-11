#!/bin/bash

# WiFi status — icon only (Material Design)
# 󰤨 nf-md-wifi | 󰤭 nf-md-wifi_off

PURPLE=0xffd699b6
RED=0xffe67e80

IP="$(ipconfig getifaddr en0 2>/dev/null)"

if [ -z "$IP" ]; then
  sketchybar --set "$NAME" icon=󰤭 icon.color=$RED
else
  sketchybar --set "$NAME" icon=󰤨 icon.color=$PURPLE
fi
