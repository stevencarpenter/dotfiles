#!/bin/bash

# Front app — shows the currently focused application icon + name + notification badge

set -euo pipefail

sketchybar --add item front_app center \
  --set front_app \
    icon.font="JetBrainsMono Nerd Font:Regular:16.0" \
    icon.color=$FG \
    icon.padding_left=8 \
    icon.padding_right=4 \
    label.font="JetBrainsMono Nerd Font:Regular:13.0" \
    label.color=$FG \
    label.padding_right=8 \
    background.color=$BG1 \
    background.corner_radius=6 \
    background.height=26 \
    background.drawing=on \
    script="$PLUGIN_DIR/front_app.sh" \
    update_freq=10 \
  --subscribe front_app front_app_switched system_woke
