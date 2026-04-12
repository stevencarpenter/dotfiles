#!/bin/bash

# AeroSpace workspace controller. Subscribed to `aerospace_workspace_change` and
# `front_app_switched` by `workspaces.controller` (see items/workspaces.sh).
# Fires ONCE per event, queries aerospace once, and emits a single batched
# `sketchybar --set ...` invocation that updates every workspace's highlight,
# bracket color, and app-icon slots.
#
# Prior design subscribed each of the 9 workspace items directly, which spawned
# 9 parallel subprocesses per event (each sourcing the 1400-line icon_map.sh).
# This controller collapses that to 1 subprocess.

set -u

BG=0xff272e33
BG2=0xff374145
GRAY=0xff7a8478
GREEN=0xffa7c080
MAX_APPS=5
WORKSPACES=(1 2 3 4 5 6 7 8 9)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/icon_map.sh"

# ─── App → Brand color map ───────────────────────────────────────────────────

color_for_app() {
  local app_lower
  app_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$app_lower" in
    ghostty)                echo "0xff7fbbb3" ;;  # ghostty teal
    *firefox*)              echo "0xffff7139" ;;  # firefox orange
    *chrome*|chromium)      echo "0xff4285f4" ;;  # google blue
    safari)                 echo "0xff006cff" ;;  # safari blue
    arc)                    echo "0xfffc6dfe" ;;  # arc pink
    *intellij*)             echo "0xfffc801d" ;;  # intellij orange
    *visual\ studio*|code)  echo "0xff007acc" ;;  # vscode blue
    zed*)                   echo "0xff8dd0e4" ;;  # zed cyan
    neovim|nvim)            echo "0xff57a143" ;;  # neovim green
    slack)                  echo "0xff611f69" ;;  # slack aubergine
    discord)                echo "0xff5865f2" ;;  # discord blurple
    obsidian)               echo "0xff7c3aed" ;;  # obsidian purple
    spotify)                echo "0xff1db954" ;;  # spotify green
    finder)                 echo "0xff4097e2" ;;  # finder blue
    mail)                   echo "0xff1a8cff" ;;  # mail blue
    messages)               echo "0xff34c759" ;;  # messages green
    calendar)               echo "0xffff3b30" ;;  # calendar red
    preview)                echo "0xff59a8eb" ;;  # preview blue
    *activity\ monitor*)    echo "0xff30d158" ;;  # activity green
    *system\ settings*|*system\ preferences*) echo "0xff8e8e93" ;; # settings gray
    1password*|*onepassword*) echo "0xff0572ec" ;; # 1password blue
    raycast)                echo "0xffff6363" ;;  # raycast red
    orbstack)               echo "0xff3b82f6" ;;  # orbstack blue
    claude)                 echo "0xffcc9b7a" ;;  # claude tan
    cursor)                 echo "0xff007acc" ;;  # cursor blue
    zoom*)                  echo "0xff2d8cff" ;;  # zoom blue
    *teams*)                echo "0xff6264a7" ;;  # teams purple
    notion)                 echo "0xffe0e0e0" ;;  # notion off-white
    wezterm)                echo "0xff4e49ee" ;;  # wezterm purple
    alacritty)              echo "0xfff0c674" ;;  # alacritty yellow
    kitty)                  echo "0xff7ebae4" ;;  # kitty blue
    iterm*|terminal)        echo "0xff34c759" ;;  # terminal green
    *steam*)                echo "0xff66c0f4" ;;  # steam light blue
    balatro)                echo "0xffee4035" ;;  # balatro red
    *)                      echo "0xff859289" ;;  # default gray
  esac
}

# ─── Determine focused workspace ─────────────────────────────────────────────

# aerospace_workspace_change sets FOCUSED_WORKSPACE. front_app_switched does
# not, so fall back to querying aerospace directly.
FOCUSED="${FOCUSED_WORKSPACE:-}"
if [ -z "$FOCUSED" ]; then
  FOCUSED="$(aerospace list-workspaces --focused 2>/dev/null)"
fi

# ─── Single aerospace query for ALL workspaces ───────────────────────────────

# Format: "<workspace>|<app-name>" one line per window. Sort+unique dedupes
# multiple windows of the same app (e.g. two IntelliJ projects) per workspace.
ALL_WINDOWS="$(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null | sort -u)"

# ─── Build a single batched sketchybar invocation ────────────────────────────

SETS=()
for sid in "${WORKSPACES[@]}"; do
  # Workspace number highlight + bracket bg
  if [ "$sid" = "$FOCUSED" ]; then
    SETS+=(--set "workspace.$sid" icon.highlight=on)
    SETS+=(--set "workspace_bracket.$sid" background.color=$BG2)
  else
    SETS+=(--set "workspace.$sid" icon.highlight=off)
    SETS+=(--set "workspace_bracket.$sid" background.color=$BG)
  fi

  # Extract apps for this workspace from the single query
  i=0
  while IFS='|' read -r ws app; do
    [ -z "$ws" ] && continue
    [ "$ws" != "$sid" ] && continue
    [ "$i" -ge "$MAX_APPS" ] && break
    __icon_map "$app"
    color="$(color_for_app "$app")"
    if [ "$sid" != "$FOCUSED" ]; then
      color=$GRAY
    fi
    SETS+=(--set "workspace.$sid.app.$i" icon="$icon_result" icon.color="$color" drawing=on)
    i=$((i + 1))
  done <<< "$ALL_WINDOWS"

  # Hide unused slots
  while [ "$i" -lt "$MAX_APPS" ]; do
    SETS+=(--set "workspace.$sid.app.$i" drawing=off)
    i=$((i + 1))
  done
done

sketchybar "${SETS[@]}"
