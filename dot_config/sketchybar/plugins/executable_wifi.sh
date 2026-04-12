#!/bin/bash

# Wi-Fi status — icon only (Material Design)
# 󰤨 nf-md-wifi | 󰤭 nf-md-wifi_off
#
# Asks macOS directly for the Wi-Fi service IP. Handles all three states:
#   - connected             → real IP
#   - on but not connected  → "none"
#   - off / service missing → empty / error
# all of which resolve to "show the disconnected icon" via the empty check.

PURPLE=0xffd699b6
RED=0xffe67e80

IP="$(networksetup -getinfo Wi-Fi 2>/dev/null \
  | awk '/^IP address:/ && $3 != "none" { print $3; exit }')"

if [ -z "$IP" ]; then
  sketchybar --set "$NAME" icon=󰤭 icon.color=$RED
else
  sketchybar --set "$NAME" icon=󰤨 icon.color=$PURPLE
fi
