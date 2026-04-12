#!/bin/bash

# Workspace indicators — bracketed groups with colored app icons
# Each workspace: [number + app icons] in one rounded rectangle

MAX_APPS=5
WORKSPACES=(1 2 3 4 5 6 7 8 9)

for sid in "${WORKSPACES[@]}"; do
  # Workspace number. icon.padding_left sets the bracket's left-edge padding.
  # icon.padding_right is the gap between the number and the first app icon
  # (and is also the right-edge padding when no apps are visible — the end-cap
  # below adds the same amount on the right to keep empty brackets symmetric).
  sketchybar --add item "workspace.$sid" left \
    --set "workspace.$sid" \
      icon="$sid" \
      icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
      icon.color="$GRAY" \
      icon.highlight_color="$GREEN" \
      icon.padding_left=6 \
      icon.padding_right=2 \
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

  # End cap — invisible, always drawn. Its padding_left (5) plus the preceding
  # element's icon.padding_right (2, from either the last app slot or the
  # workspace number when empty) gives a constant 7px right-edge padding that
  # matches 6px of icon.padding_left + 1px balance for the icon's visual
  # center-of-mass sitting slightly left of its glyph box.
  sketchybar --add item "workspace.$sid.end" left \
    --set "workspace.$sid.end" \
      icon.drawing=off \
      label.drawing=off \
      background.drawing=off \
      padding_left=5 \
      padding_right=0 \
      click_script="aerospace workspace $sid"

  # Bracket wrapping number + all app slots + end cap
  sketchybar --add bracket "workspace_bracket.$sid" \
      "workspace.$sid" \
      "workspace.$sid.app.0" \
      "workspace.$sid.app.1" \
      "workspace.$sid.app.2" \
      "workspace.$sid.app.3" \
      "workspace.$sid.app.4" \
      "workspace.$sid.end" \
    --set "workspace_bracket.$sid" \
      background.color="$BG" \
      background.drawing=on \
      background.height=26 \
      background.corner_radius=8
done
