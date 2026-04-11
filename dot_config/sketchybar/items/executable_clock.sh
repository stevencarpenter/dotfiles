#!/bin/bash

# Clock — 24h local time
sketchybar --add item clock right \
  --set clock \
    icon=󰥔 \
    icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
    icon.color=$BLUE \
    icon.padding_right=6 \
    icon.padding_left=4 \
    label.font="JetBrainsMono Nerd Font:Regular:12.0" \
    label.color=$FG \
    label.padding_right=12 \
    background.drawing=off \
    update_freq=1 \
    script="$PLUGIN_DIR/clock.sh" \
  --subscribe clock mouse.entered mouse.exited

# Calendar — US date, hover shows UTC popup
sketchybar --add item calendar right \
  --set calendar \
    icon=󰃭 \
    icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
    icon.color=$AQUA \
    icon.padding_right=4 \
    label.font="JetBrainsMono Nerd Font:Regular:12.0" \
    label.color=$FG \
    background.drawing=off \
    popup.background.color=$BG1 \
    popup.background.corner_radius=8 \
    popup.background.border_color=$BG3 \
    popup.background.border_width=1 \
    popup.background.drawing=on \
    popup.horizontal=on \
    update_freq=30 \
    script="$PLUGIN_DIR/clock.sh" \
  --subscribe calendar mouse.entered mouse.exited

# UTC date inside popup
sketchybar --add item calendar.utc_date popup.calendar \
  --set calendar.utc_date \
    icon=󰃭 \
    icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
    icon.color=$GRAY2 \
    icon.padding_left=8 \
    icon.padding_right=6 \
    label.font="JetBrainsMono Nerd Font:Regular:12.0" \
    label.color=$FG

# UTC time inside popup
sketchybar --add item calendar.utc_time popup.calendar \
  --set calendar.utc_time \
    icon=󰥔 \
    icon.font="JetBrainsMono Nerd Font:Bold:13.0" \
    icon.color=$GRAY2 \
    icon.padding_right=6 \
    label.font="JetBrainsMono Nerd Font:Regular:12.0" \
    label.color=$FG \
    label.padding_right=8
