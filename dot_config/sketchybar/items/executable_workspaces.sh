#!/bin/bash

# Workspace indicators — integrated with AeroSpace
# Highlights the focused workspace, dims empty ones

WORKSPACES=(1 2 3 4 5 6 7 8 9)

for sid in "${WORKSPACES[@]}"; do
  sketchybar --add item "workspace.$sid" left \
    --set "workspace.$sid" \
      icon="$sid" \
      icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
      icon.color=$GRAY \
      icon.highlight_color=$GREEN \
      icon.padding_left=8 \
      icon.padding_right=8 \
      background.color=$BG \
      background.drawing=on \
      label.drawing=off \
      click_script="aerospace workspace $sid" \
      script="$PLUGIN_DIR/aerospace.sh $sid" \
    --subscribe "workspace.$sid" aerospace_workspace_change
done
