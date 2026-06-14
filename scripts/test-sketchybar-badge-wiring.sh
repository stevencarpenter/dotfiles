#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sketchybarrc="${repo_root}/dot_config/sketchybar/executable_sketchybarrc"
workspaces_item="${repo_root}/dot_config/sketchybar/items/executable_workspaces.sh"
aerospace_plugin="${repo_root}/dot_config/sketchybar/plugins/executable_aerospace.sh"
badge_plugin="${repo_root}/dot_config/sketchybar/plugins/executable_app_badge.sh"

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  case "$(<"${file}")" in
    *"${needle}"*) ;;
    *)
      echo "${message}" >&2
      exit 1
      ;;
  esac
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  case "$(<"${file}")" in
    *"${needle}"*)
      echo "${message}" >&2
      exit 1
      ;;
    *) ;;
  esac
}

assert_contains "${sketchybarrc}" \
  'source "$ITEM_DIR/workspaces.sh"' \
  "expected sketchybarrc to source workspace items (badge feature deploy path)"

assert_not_contains "${sketchybarrc}" \
  'source "$ITEM_DIR/front_app.sh"' \
  "expected sketchybarrc not to source removed front_app item"

assert_not_contains "${sketchybarrc}" \
  'source "$ITEM_DIR/slack.sh"' \
  "expected sketchybarrc not to source removed slack item"

assert_contains "${workspaces_item}" \
  'source "$PLUGIN_DIR/app_badge.sh"' \
  "expected workspaces item to source shared badge constants"

assert_contains "${workspaces_item}" \
  'SKETCHYBAR_WS_BADGE_LABEL_PADDING_LEFT' \
  "expected workspaces item to use shared badge layout constants"

assert_contains "${aerospace_plugin}" \
  'source "$SCRIPT_DIR/app_badge.sh"' \
  "expected Aerospace plugin to source the shared badge utility"

assert_contains "${aerospace_plugin}" \
  'workspace_app_has_badge "$app"' \
  "expected Aerospace plugin to use has_app_badge_label via workspace_app_has_badge"

assert_contains "${aerospace_plugin}" \
  'SKETCHYBAR_WS_BADGE_LABEL_PADDING_LEFT' \
  "expected Aerospace plugin to use shared badge layout constants"

assert_not_contains "${aerospace_plugin}" \
  'normalize_app_badge_label "$raw"' \
  "expected Aerospace plugin not to normalize counts it never displays"

# app_badge.sh must be usable as both a CLI and a sourceable function library.
set +e +u +o pipefail
source "${badge_plugin}"
if [[ $- == *e* || $- == *u* ]] || set -o | awk '$1 == "pipefail" && $2 == "on" { found = 1 } END { exit !found }'; then
  echo "expected sourcing app_badge.sh not to mutate caller shell options" >&2
  exit 1
fi
set -euo pipefail

assert_has_badge() {
  local raw="$1"
  local expected="$2"
  local actual

  if has_app_badge_label "${raw}"; then
    actual=0
  else
    actual=1
  fi
  if [[ "${actual}" -ne "${expected}" ]]; then
    {
      printf 'expected raw badge %q has-badge=%s\n' "${raw}" "${expected}"
      printf 'actual: %s\n' "${actual}"
    } >&2
    exit 1
  fi
}

assert_has_badge "" 1
assert_has_badge "•" 0
assert_has_badge "42" 0
assert_has_badge "100" 0
assert_has_badge "0" 1
assert_has_badge "Inbox" 1

assert_normalized() {
  local raw="$1"
  local expected="$2"
  local actual

  actual="$(normalize_app_badge_label "${raw}")"
  if [[ "${actual}" != "${expected}" ]]; then
    {
      printf 'expected raw badge %q to normalize to %q\n' "${raw}" "${expected}"
      printf 'actual: %q\n' "${actual}"
    } >&2
    exit 1
  fi
}

assert_normalized "" ""
assert_normalized "•" "•"
assert_normalized "42" "42"
assert_normalized "100" "99+"
assert_normalized "0" ""
assert_normalized "Inbox" ""

echo "sketchybar badge deployment wiring and normalization are covered"
