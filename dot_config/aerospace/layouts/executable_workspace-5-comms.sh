#!/bin/bash
# Workspace 5: Comms — 2x1 left, 1 right
#
#   ┌──────────┬──────────┐
#   │   Mail   │          │
#   ├──────────┤ Messages │
#   │ Calendar │          │
#   └──────────┴──────────┘
#
# Usage: ~/.config/aerospace/layouts/workspace-5-comms.sh

set -euo pipefail

WORKSPACE=5

get_window_id() {
  aerospace list-windows --workspace "$WORKSPACE" --format '%{window-id}|%{app-name}' \
    | grep -i "$1" | head -1 | cut -d'|' -f1
}

CALENDAR_ID="$(get_window_id 'Calendar')"

aerospace workspace "$WORKSPACE"
aerospace flatten-workspace-tree

# Join Calendar under Mail (left vertical pair)
if [ -n "$CALENDAR_ID" ]; then
  aerospace focus --window-id "$CALENDAR_ID"
  aerospace join-with up
fi

aerospace balance-sizes

echo "Workspace $WORKSPACE arranged: Mail/Calendar | Messages"
