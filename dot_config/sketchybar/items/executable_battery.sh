#!/bin/bash

# Battery indicator — percentage and icon

sketchybar --add item battery right \
  --set battery \
    icon.font="JetBrainsMono Nerd Font:Regular:14.0" \
    icon.color=$GREEN \
    icon.padding_right=4 \
    label.font="JetBrainsMono Nerd Font:Regular:13.0" \
    label.color=$FG \
    update_freq=120 \
    script="$PLUGIN_DIR/battery.sh" \
  --subscribe battery power_source_change system_woke
