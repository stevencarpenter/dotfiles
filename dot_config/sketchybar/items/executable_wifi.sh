#!/bin/bash

# WiFi — icon-only (Material Design icons)

sketchybar --add item wifi right \
  --set wifi \
    icon=󰤨 \
    icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
    icon.color=$PURPLE \
    icon.padding_left=4 \
    icon.padding_right=4 \
    label.drawing=off \
    background.drawing=off \
    update_freq=30 \
    script="$PLUGIN_DIR/wifi.sh" \
  --subscribe wifi wifi_change system_woke
