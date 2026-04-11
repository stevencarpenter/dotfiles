#!/bin/bash

# Volume — mute indicator only (Material Design icons)

sketchybar --add item volume right \
  --set volume \
    icon=󰕾 \
    icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
    icon.color=$ORANGE \
    icon.padding_left=8 \
    icon.padding_right=4 \
    label.drawing=off \
    background.drawing=off \
    script="$PLUGIN_DIR/volume.sh" \
  --subscribe volume volume_change
