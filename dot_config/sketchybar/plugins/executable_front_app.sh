#!/bin/bash

# Front app change handler — updates the label to show the focused app name

set -euo pipefail

# INFO is set by sketchybar's front_app_switched event; absent on manual
# invocation, so default to empty under set -u.
if [ -n "${INFO:-}" ]; then
  sketchybar --set "$NAME" label="$INFO"
fi
