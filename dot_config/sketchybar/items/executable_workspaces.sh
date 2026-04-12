#!/bin/bash

# Workspace indicators — bracketed groups with colored app icons
# Each workspace: [number + app icons] in one rounded rectangle

MAX_APPS=5
WORKSPACES=(1 2 3 4 5 6 7 8 9)

for sid in "${WORKSPACES[@]}"; do
  # Workspace number
  sketchybar --add item "workspace.$sid" left \
    --set "workspace.$sid" \
      icon="$sid" \
      icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
      icon.color="$GRAY" \
      icon.highlight_color="$GREEN" \
      icon.padding_left=6 \
      icon.padding_right=6 \
      label.drawing=off \
      background.drawing=off \
      click_script="aerospace workspace $sid" \
      script="$PLUGIN_DIR/aerospace.sh $sid" \
    --subscribe "workspace.$sid" aerospace_workspace_change front_app_switched

  # Pre-allocate app icon slots
  for i in $(seq 0 $((MAX_APPS - 1))); do
    sketchybar --add item "workspace.$sid.app.$i" left \
      --set "workspace.$sid.app.$i" \
        icon.font="sketchybar-app-font:Regular:14.0" \
        icon.padding_left=2 \
        icon.padding_right=2 \
        label.drawing=off \
        background.drawing=off \
        padding_left=0 \
        padding_right=0 \
        click_script="aerospace workspace $sid" \
        drawing=off
  done

  # Bracket wrapping number + all app slots
  sketchybar --add bracket "workspace_bracket.$sid" \
      "workspace.$sid" \
      "workspace.$sid.app.0" \
      "workspace.$sid.app.1" \
      "workspace.$sid.app.2" \
      "workspace.$sid.app.3" \
      "workspace.$sid.app.4" \
    --set "workspace_bracket.$sid" \
      background.color="$BG" \
      background.drawing=on \
      background.height=26 \
      background.corner_radius=8
done
