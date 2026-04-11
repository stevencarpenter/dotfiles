#!/bin/bash

# Clock — time and date on the right side

sketchybar --add item clock right \
  --set clock \
    icon= \
    icon.color=$BLUE \
    icon.padding_right=4 \
    label.font="JetBrainsMono Nerd Font:Regular:13.0" \
    label.color=$FG \
    update_freq=30 \
    script="$PLUGIN_DIR/clock.sh"
