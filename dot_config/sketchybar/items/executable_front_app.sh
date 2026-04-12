#!/bin/bash

# Front app — shows the currently focused application name

sketchybar --add item front_app center \
  --set front_app \
    icon.drawing=off \
    label.font="JetBrainsMono Nerd Font:Regular:13.0" \
    label.color=$FG \
    script="$PLUGIN_DIR/front_app.sh" \
  --subscribe front_app front_app_switched
