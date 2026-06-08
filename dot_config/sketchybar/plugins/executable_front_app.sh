#!/bin/bash

# Front app change handler — updates icon, label, and notification badge for focused app

set -euo pipefail

PLUGIN_DIR="$CONFIG_DIR/plugins"

# INFO is set by sketchybar's front_app_switched event; absent on manual
# invocation, so default to empty under set -u.
if [ -n "${INFO:-}" ]; then
  app_name="$INFO"

  # Get icon from icon_map
  icon=$("$PLUGIN_DIR/icon_map.sh" "$app_name")

  # Get badge count
  badge=$("$PLUGIN_DIR/app_badge.sh" "$app_name")

  # Update icon
  sketchybar --set "$NAME" icon="$icon"

  # Update label with badge if present
  if [ -n "$badge" ]; then
    sketchybar --set "$NAME" label="${app_name}  ${badge}"
  else
    sketchybar --set "$NAME" label="$app_name"
  fi
fi
