#!/bin/bash

# WiFi status — icon only (Material Design)
# 󰤨 nf-md-wifi | 󰤭 nf-md-wifi_off

PURPLE=0xffd699b6
RED=0xffe67e80

# Resolve the Wi-Fi hardware port dynamically (en0 is not always Wi-Fi — can be
# Ethernet on desktops or reassigned on laptops with external adapters).
# Match both "Wi-Fi" (modern macOS) and "AirPort" (10.6 and earlier, and some
# non-en-US locales still use the older label).
WIFI_IF="$(networksetup -listallhardwareports 2>/dev/null \
  | awk '/^Hardware Port: (Wi-Fi|AirPort)$/ { getline; print $2; exit }')"

IP="$(ipconfig getifaddr "${WIFI_IF:-en0}" 2>/dev/null)"

if [ -z "$IP" ]; then
  sketchybar --set "$NAME" icon=󰤭 icon.color=$RED
else
  sketchybar --set "$NAME" icon=󰤨 icon.color=$PURPLE
fi
