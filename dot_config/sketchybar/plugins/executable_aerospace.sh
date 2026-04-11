#!/bin/bash

# AeroSpace workspace change handler
# Called with workspace ID as $1, receives FOCUSED_WORKSPACE env var from AeroSpace

BG=0xff2f383e
GREEN=0xffa7c080
GRAY=0xff859289
FG=0xffd3c6aa

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set "$NAME" \
    icon.highlight=on \
    background.color=0xff3a4248
else
  sketchybar --set "$NAME" \
    icon.highlight=off \
    background.color=$BG
fi
