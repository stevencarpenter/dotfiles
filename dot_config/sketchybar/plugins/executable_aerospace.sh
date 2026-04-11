#!/bin/bash

# AeroSpace workspace change handler
# Creates per-app colored icons using sketchybar-app-font

BG=0xff272e33
BG2=0xff374145
GRAY=0xff7a8478
FG=0xffd3c6aa
GREEN=0xffa7c080
MAX_APPS=5

SID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# FOCUSED_WORKSPACE is only set by aerospace_workspace_change events.
# For front_app_switched and other events, query aerospace directly.
if [ -z "$FOCUSED_WORKSPACE" ]; then
  FOCUSED_WORKSPACE="$(aerospace list-workspaces --focused 2>/dev/null)"
fi

source "$SCRIPT_DIR/icon_map.sh"

# ─── App → Brand color map ───────────────────────────────────────────────────

color_for_app() {
  local app_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
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

# ─── Query windows on this workspace ──────────────────────────────────────────

APPS="$(aerospace list-windows --workspace "$SID" --format '%{app-name}' 2>/dev/null)"

# Deduplicate and collect into array
APP_LIST=()
if [ -n "$APPS" ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    APP_LIST+=("$app")
  done <<< "$(echo "$APPS" | sort -u)"
fi

APP_COUNT=${#APP_LIST[@]}

# ─── Update workspace number + bracket ───────────────────────────────────────

if [ "$SID" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set "$NAME" icon.highlight=on
  sketchybar --set "workspace_bracket.$SID" background.color=$BG2
else
  sketchybar --set "$NAME" icon.highlight=off
  sketchybar --set "workspace_bracket.$SID" background.color=$BG
fi

# ─── Update app icon slots ───────────────────────────────────────────────────

for i in $(seq 0 $((MAX_APPS - 1))); do
  SLOT="workspace.$SID.app.$i"

  if [ "$i" -lt "$APP_COUNT" ]; then
    app="${APP_LIST[$i]}"
    __icon_map "$app"
    COLOR="$(color_for_app "$app")"

    # Dim colors on unfocused workspaces
    if [ "$SID" != "$FOCUSED_WORKSPACE" ]; then
      COLOR=$GRAY
    fi

    sketchybar --set "$SLOT" \
      icon="$icon_result" \
      icon.color="$COLOR" \
      drawing=on
  else
    sketchybar --set "$SLOT" drawing=off
  fi
done
