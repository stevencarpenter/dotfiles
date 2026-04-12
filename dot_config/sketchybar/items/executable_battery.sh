#!/bin/bash

# Battery — Material Design icons with percentage and time

set -euo pipefail

sketchybar --add item battery right \
  --set battery \
    icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
    icon.color=$GREEN \
    icon.padding_right=4 \
    label.font="JetBrainsMono Nerd Font:Regular:12.0" \
    label.color=$FG \
    background.drawing=off \
    update_freq=120 \
    script="$PLUGIN_DIR/battery.sh" \
  --subscribe battery power_source_change system_woke
