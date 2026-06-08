#!/bin/bash

# Slack — shows Slack icon with notification badge count

set -euo pipefail

sketchybar --add item slack center \
  --set slack \
    icon=":slack:" \
    icon.font="JetBrainsMono Nerd Font:Regular:16.0" \
    icon.color=0xff611f69 \
    label.font="JetBrainsMono Nerd Font:Bold:11.0" \
    label.color=0xffffffff \
    label.padding_left=4 \
    label.padding_right=4 \
    background.color=0xffe67e80 \
    background.corner_radius=9 \
    background.height=18 \
    background.drawing=off \
    script="$PLUGIN_DIR/slack.sh" \
    update_freq=30 \
  --subscribe slack system_woke
