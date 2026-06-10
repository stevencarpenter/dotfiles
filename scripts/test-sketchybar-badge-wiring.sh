#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
slack_item="${repo_root}/dot_config/sketchybar/items/executable_slack.sh"
slack_plugin="${repo_root}/dot_config/sketchybar/plugins/executable_slack.sh"
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

assert_contains "${slack_item}" \
  "--subscribe slack slack system_woke" \
  "expected Slack item to subscribe to both slack and system_woke events"

assert_contains "${slack_plugin}" \
  'source "$SCRIPT_DIR/app_badge.sh"' \
  "expected Slack plugin to source the shared badge utility"
assert_contains "${slack_plugin}" \
  'get_app_badge "Slack"' \
  "expected Slack plugin to fetch Slack badge via shared utility"
assert_not_contains "${slack_plugin}" \
  'lsappinfo info -only StatusLabel "Slack"' \
  "expected Slack plugin not to duplicate lsappinfo badge parsing"

assert_contains "${aerospace_plugin}" \
  'source "$SCRIPT_DIR/app_badge.sh"' \
  "expected Aerospace plugin to source the shared badge utility"
assert_contains "${aerospace_plugin}" \
  'normalize_app_badge_label "$raw"' \
  "expected Aerospace plugin to use shared badge normalization"

# app_badge.sh must be usable as both a CLI and a sourceable function library.
set +e +u +o pipefail
source "${badge_plugin}"
if [[ $- == *e* || $- == *u* ]] || set -o | awk '$1 == "pipefail" && $2 == "on" { found = 1 } END { exit !found }'; then
  echo "expected sourcing app_badge.sh not to mutate caller shell options" >&2
  exit 1
fi
set -euo pipefail

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

echo "sketchybar badge event wiring and normalization are covered"
