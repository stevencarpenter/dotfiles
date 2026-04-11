#!/bin/bash

# AeroSpace workspace change handler
# Called with workspace ID as $1, receives FOCUSED_WORKSPACE env var from AeroSpace
# Uses sketchybar-app-font for app icons (brew install --cask font-sketchybar-app-font)

BG=0xff272e33
BG2=0xff374145
GRAY=0xff7a8478
FG=0xffd3c6aa

SID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/icon_map.sh"

# ─── Query windows on this workspace ──────────────────────────────────────────

APPS="$(aerospace list-windows --workspace "$SID" --format '%{app-name}' 2>/dev/null)"

# Build icon string — deduplicate with sort -u
ICON_STRIP=""
if [ -n "$APPS" ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    __icon_map "$app"
    ICON_STRIP+=" $icon_result"
  done <<< "$(echo "$APPS" | sort -u)"
fi

# ─── Update item ──────────────────────────────────────────────────────────────

if [ "$SID" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set "$NAME" \
    icon.highlight=on \
    background.color=$BG2 \
    label="$ICON_STRIP" \
    label.drawing=on \
    label.color=$FG
else
  if [ -n "$ICON_STRIP" ]; then
    sketchybar --set "$NAME" \
      icon.highlight=off \
      background.color=$BG \
      label="$ICON_STRIP" \
      label.drawing=on \
      label.color=$GRAY
  else
    sketchybar --set "$NAME" \
      icon.highlight=off \
      background.color=$BG \
      label.drawing=off
  fi
fi
