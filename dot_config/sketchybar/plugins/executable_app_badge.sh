#!/bin/bash

# Generic app badge fetcher — queries macOS dock badge via lsappinfo.
# Usage: app_badge.sh <app_name>
# Output: badge label (empty, "•", or numeric/99+ count)

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
