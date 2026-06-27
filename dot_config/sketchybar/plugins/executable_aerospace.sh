#!/usr/bin/env bash

# AeroSpace workspace controller. Subscribed to `aerospace_workspace_change` and
# `front_app_switched` by `workspaces.controller` (see items/workspaces.sh).
# Fires ONCE per event, queries aerospace once, and emits a single batched
# `sketchybar --set ...` invocation that updates every workspace's highlight,
# bracket color, and app-icon slots with notification badges.
#
# Requires bash >= 4 for associative arrays. Resolves to brew bash (5.x) via
# /opt/homebrew/bin on sketchybar's inherited PATH; the system /bin/bash (3.2)
# would fail fast on the `declare -A` below.

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "aerospace.sh: needs bash >= 4 (got $BASH_VERSION)" >&2
  exit 1
fi

BG=0xff272e33
BG2=0xff374145
GRAY=0xff7a8478
RED=0xffe67e80
MAX_APPS=5
WORKSPACES=(1 2 3 4 5 6 7 8 9)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/icon_map.sh"
source "$SCRIPT_DIR/app_badge.sh"

machine_env="$SCRIPT_DIR/../machine.env"
if [[ -r "$machine_env" ]]; then
  # shellcheck disable=SC1090
  source "$machine_env"
fi
SKETCHYBAR_WORKSPACE_BADGES="${SKETCHYBAR_WORKSPACE_BADGES:-1}"

# ─── App → Brand color map ───────────────────────────────────────────────────

color_for_app() {
  local app="${1,,}"  # bash 4+ lowercase expansion, no tr subshell
  case "$app" in
    ghostty)                            echo "0xff7fbbb3" ;;  # ghostty teal
    *firefox*)                          echo "0xffff7139" ;;  # firefox orange
    *chrome*|chromium)                  echo "0xff4285f4" ;;  # google blue
    safari)                             echo "0xff006cff" ;;  # safari blue
    arc)                                echo "0xfffc6dfe" ;;  # arc pink
    *intellij*)                         echo "0xfffc801d" ;;  # intellij orange
    *"visual studio"*|code)             echo "0xff007acc" ;;  # vscode blue
    zed*)                               echo "0xff8dd0e4" ;;  # zed cyan
    neovim|nvim)                        echo "0xff57a143" ;;  # neovim green
    slack)                              echo "0xff611f69" ;;  # slack aubergine
    discord)                            echo "0xff5865f2" ;;  # discord blurple
    obsidian)                           echo "0xff7c3aed" ;;  # obsidian purple
    spotify)                            echo "0xff1db954" ;;  # spotify green
    finder)                             echo "0xff4097e2" ;;  # finder blue
    mail)                               echo "0xff1a8cff" ;;  # mail blue
    messages)                           echo "0xff34c759" ;;  # messages green
    calendar)                           echo "0xffff3b30" ;;  # calendar red
    preview)                            echo "0xff59a8eb" ;;  # preview blue
    *"activity monitor"*)               echo "0xff30d158" ;;  # activity green
    *"system settings"*|*"system preferences"*) echo "0xff8e8e93" ;;  # settings gray
    1password*|*onepassword*)           echo "0xff0572ec" ;;  # 1password blue
    raycast)                            echo "0xffff6363" ;;  # raycast red
    orbstack)                           echo "0xff3b82f6" ;;  # orbstack blue
    claude)                             echo "0xffcc9b7a" ;;  # claude tan
    codex)                              echo "0xff10a37f" ;;  # openai green
    cursor)                             echo "0xff007acc" ;;  # cursor blue
    *"screen sharing"*)                 echo "0xff4097e2" ;;  # screen sharing blue
    zoom*)                              echo "0xff2d8cff" ;;  # zoom blue
    *teams*)                            echo "0xff6264a7" ;;  # teams purple
    notion)                             echo "0xffe0e0e0" ;;  # notion off-white
    wezterm)                            echo "0xff4e49ee" ;;  # wezterm purple
    alacritty)                          echo "0xfff0c674" ;;  # alacritty yellow
    kitty)                              echo "0xff7ebae4" ;;  # kitty blue
    iterm*|terminal)                    echo "0xff34c759" ;;  # terminal green
    *steam*)                            echo "0xff66c0f4" ;;  # steam light blue
    balatro)                            echo "0xffee4035" ;;  # balatro red
    *)                                  echo "0xff859289" ;;  # default gray
  esac
}

# ─── Get dock badge labels via one batched lsappinfo call ────────────────────

# Each lsappinfo invocation costs ~270ms of spawn+IPC on this box, so per-app
# calls would add seconds per event. lsappinfo accepts repeated verbs in one
# invocation and prints exactly one "StatusLabel"=... line per verb, in
# argument order (non-running apps still emit a line), so one call fetches
# every app and the lines map back by index. If the one-line-per-app invariant
# ever breaks, badges go blank for this tick instead of misattributing.
declare -A BADGE_CACHE

workspace_badges_enabled() {
  case "${SKETCHYBAR_WORKSPACE_BADGES:-1}" in
    0|false|False|FALSE|no|No|NO|off|Off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

prefetch_badges() {
  workspace_badges_enabled || return 0
  local apps=("$@")
  (( ${#apps[@]} == 0 )) && return
  local args=() app
  for app in "${apps[@]}"; do
    args+=(info -only StatusLabel "$app")
  done
  local lines=()
  mapfile -t lines < <(lsappinfo "${args[@]}" 2>/dev/null || true)
  (( ${#lines[@]} != ${#apps[@]} )) && {
    echo "aerospace.sh: badge prefetch line count mismatch (${#lines[@]} vs ${#apps[@]}), skipping badges" >&2
    return
  }
  local i label
  for i in "${!apps[@]}"; do
    label=""
    if [[ "${lines[$i]}" =~ \"label\"=\"([^\"]*)\" ]]; then
      label="${BASH_REMATCH[1]}"
    fi
    BADGE_CACHE[${apps[$i]}]="$label"
  done
}

# Normalizes the prefetched raw label into badge_result (dot or empty).
workspace_app_has_badge() {
  workspace_badges_enabled || return 1
  has_app_badge_label "${BADGE_CACHE[$1]-}"
}

# ─── Determine focused workspace ─────────────────────────────────────────────

# aerospace_workspace_change sets FOCUSED_WORKSPACE; other events don't.
FOCUSED="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null || true)}"

# ─── Single aerospace query + group apps per workspace ───────────────────────

declare -A APPS_BY_WS  # ws → newline-separated unique app names

while IFS='|' read -r ws app; do
  [[ -z "$ws" || -z "$app" ]] && continue
  existing="${APPS_BY_WS[$ws]:-}"
  # Dedupe — only append if we haven't seen this app on this workspace yet.
  if [[ $'\n'"$existing"$'\n' != *$'\n'"$app"$'\n'* ]]; then
    APPS_BY_WS[$ws]="${existing:+$existing$'\n'}$app"
  fi
done < <(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null || true)

# Unique apps across all workspaces → one badge prefetch for the whole run.
declare -A SEEN_APPS
ALL_APPS=()
for ws in "${!APPS_BY_WS[@]}"; do
  while IFS= read -r app; do
    [[ -z "$app" || -n "${SEEN_APPS[$app]+x}" ]] && continue
    SEEN_APPS[$app]=1
    ALL_APPS+=("$app")
  done <<<"${APPS_BY_WS[$ws]}"
done
prefetch_badges "${ALL_APPS[@]}"

# ─── Build a single batched sketchybar invocation ────────────────────────────

SETS=()
for sid in "${WORKSPACES[@]}"; do
  # Workspace number highlight + bracket bg
  if [[ "$sid" == "$FOCUSED" ]]; then
    SETS+=(--set "workspace.$sid" icon.highlight=on
           --set "workspace_bracket.$sid" "background.color=$BG2")
  else
    SETS+=(--set "workspace.$sid" icon.highlight=off
           --set "workspace_bracket.$sid" "background.color=$BG")
  fi

  # App icon slots
  apps_raw="${APPS_BY_WS[$sid]:-}"
  i=0
  if [[ -n "$apps_raw" ]]; then
    mapfile -t apps <<<"$apps_raw"
    for app in "${apps[@]}"; do
      (( i >= MAX_APPS )) && break
      __icon_map "$app"
      if [[ "$sid" == "$FOCUSED" ]]; then
        color="$(color_for_app "$app")"
      else
        color=$GRAY
      fi

      # Notification badge dot when dock reports unread/count for this app.
      if workspace_app_has_badge "$app"; then
        SETS+=(--set "workspace.$sid.app.$i"
               "icon=$icon_result" "icon.color=$color"
               icon.padding_right=$SKETCHYBAR_WS_BADGE_ICON_PADDING_RIGHT
               "label=$SKETCHYBAR_WS_BADGE_DOT"
               "label.font=$SKETCHYBAR_WS_BADGE_LABEL_FONT"
               "label.color=$RED"
               "label.padding_left=$SKETCHYBAR_WS_BADGE_LABEL_PADDING_LEFT"
               "label.padding_right=$SKETCHYBAR_WS_BADGE_LABEL_PADDING_RIGHT"
               "label.y_offset=$SKETCHYBAR_WS_BADGE_LABEL_Y_OFFSET"
               "label.drawing=on"
               background.drawing=off
               drawing=on)
      else
        SETS+=(--set "workspace.$sid.app.$i"
               "icon=$icon_result" "icon.color=$color"
               icon.padding_right=0
               label="" label.drawing=off label.padding_left=0
               background.drawing=off
               drawing=on)
      fi
      # NOTE: `((i++))` under `set -euo pipefail` exits with status 1 when
      # the pre-increment value is 0 (post-increment returns old value →
      # arithmetic context reads 0 as false → exit 1). Use arithmetic
      # assignment instead, which is always status 0.
      i=$((i+1))
    done
  fi
  while (( i < MAX_APPS )); do
    SETS+=(--set "workspace.$sid.app.$i" drawing=off)
    i=$((i+1))
  done
done

sketchybar "${SETS[@]}"
