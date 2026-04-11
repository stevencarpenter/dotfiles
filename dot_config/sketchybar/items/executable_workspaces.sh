#!/bin/bash

# Workspace indicators — integrated with AeroSpace
# Shows workspace number + nerd font icons for apps on each workspace

WORKSPACES=(1 2 3 4 5 6 7 8 9)

for sid in "${WORKSPACES[@]}"; do
  sketchybar --add item "workspace.$sid" left \
    --set "workspace.$sid" \
      icon="$sid" \
      icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
      icon.color=$GRAY \
      icon.highlight_color=$GREEN \
      icon.padding_left=8 \
      icon.padding_right=2 \
      label.font="sketchybar-app-font:Regular:14.0" \
      label.color=$GRAY \
      label.padding_right=6 \
      label.drawing=off \
      background.color=$BG \
      background.drawing=on \
      click_script="aerospace workspace $sid" \
      script="$PLUGIN_DIR/aerospace.sh $sid" \
    --subscribe "workspace.$sid" aerospace_workspace_change front_app_switched
done
