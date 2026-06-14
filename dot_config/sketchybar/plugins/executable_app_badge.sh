#!/bin/bash

# Shared macOS dock badge helpers for SketchyBar plugins.
# Source for functions/constants; run as CLI: app_badge.sh <app_name>

# Workspace icon notification dot styling — keep in sync with aerospace.sh --set.
SKETCHYBAR_WS_BADGE_DOT='•'
SKETCHYBAR_WS_BADGE_LABEL_FONT='JetBrainsMono Nerd Font:Bold:16.0'
SKETCHYBAR_WS_BADGE_LABEL_PADDING_LEFT=-4
SKETCHYBAR_WS_BADGE_LABEL_PADDING_RIGHT=3
SKETCHYBAR_WS_BADGE_LABEL_Y_OFFSET=4
SKETCHYBAR_WS_BADGE_ICON_PADDING_RIGHT=2

normalize_app_badge_label() {
  local badge_label="${1:-}"

  case "$badge_label" in
    "" )
      echo ""
      ;;
    "•" )
      echo "•"
      ;;
    * )
      if [[ "$badge_label" =~ ^[0-9]+$ ]] && [ "$badge_label" -gt 0 ]; then
        if [ "$badge_label" -gt 99 ]; then
          echo "99+"
        else
          echo "$badge_label"
        fi
      else
        echo ""
      fi
      ;;
  esac
}

# True when lsappinfo's raw StatusLabel means "show a badge" (dot or count).
has_app_badge_label() {
  local raw="${1:-}"

  case "$raw" in
    "" ) return 1 ;;
    "•" ) return 0 ;;
    * )
      [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -gt 0 ]
      ;;
  esac
}

get_app_badge() {
  local app_name="${1:-}"
  local badge_label

  if [ -z "$app_name" ]; then
    return 1
  fi

  badge_label=$(lsappinfo info -only StatusLabel "$app_name" 2>/dev/null | sed -E 's/.*"label"="([^"]*)".*/\1/')
  normalize_app_badge_label "$badge_label"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  get_app_badge "${1:-}"
fi
