#!/bin/bash

# Generic app badge fetcher — queries macOS dock badge via lsappinfo
# Usage: app_badge.sh <app_name>
# Output: badge label (empty, "•", or numeric count)

set -euo pipefail

app_name="${1:-}"

if [ -z "$app_name" ]; then
  exit 1
fi

# Get badge label from lsappinfo
badge_label=$(lsappinfo info -only StatusLabel "$app_name" 2>/dev/null | sed -E 's/.*"label"="([^"]*)".*/\1/')

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
