#!/bin/bash

# Front app change handler — updates the label to show the focused app name

if [ -n "$INFO" ]; then
  sketchybar --set "$NAME" label="$INFO"
fi
