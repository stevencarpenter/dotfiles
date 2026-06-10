#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
item_file="${repo_root}/dot_config/sketchybar/items/executable_clock.sh"
plugin_file="${repo_root}/dot_config/sketchybar/plugins/executable_clock.sh"

item_source="$(<"${item_file}")"

require_subscription() {
  local item_name="$1"
  local expected="--subscribe ${item_name} mouse.entered mouse.exited mouse.exited.global"

  case "${item_source}" in
    *"${expected}"*) ;;
    *)
      echo "expected ${item_name} to hide the UTC popup on mouse.exited.global" >&2
      exit 1
      ;;
  esac
}

require_subscription clock
require_subscription calendar

# Popup rows must stay passive: a mouse.exited subscription on a row fires
# when the cursor crosses to the other row inside the horizontal popup and
# closes the popup mid-hover. mouse.exited.global on clock/calendar handles
# leaving the popup.
require_popup_item_passive() {
  local item_name="$1"

  case "${item_source}" in
    *"--subscribe ${item_name}"*)
      echo "expected ${item_name} to have no event subscriptions (closing is handled by mouse.exited.global)" >&2
      exit 1
      ;;
    *) ;;
  esac
}

require_popup_item_passive calendar.utc_date
require_popup_item_passive calendar.utc_time

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/sketchybar-clock-popup.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

log_file="${tmpdir}/sketchybar.log"
fake_sketchybar="${tmpdir}/sketchybar"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "${SKETCHYBAR_TEST_LOG}"' \
  > "${fake_sketchybar}"
chmod +x "${fake_sketchybar}"

assert_plugin_hides_for_sender() {
  local sender="$1"

  : > "${log_file}"
  SKETCHYBAR_TEST_LOG="${log_file}" \
    PATH="${tmpdir}:${PATH}" \
    SENDER="${sender}" \
    bash "${plugin_file}"

  case "$(<"${log_file}")" in
    *"--set calendar popup.drawing=off"*) ;;
    *)
      echo "expected ${sender} to hide the calendar popup" >&2
      exit 1
      ;;
  esac
}

assert_plugin_hides_for_sender mouse.exited
assert_plugin_hides_for_sender mouse.exited.global

echo "sketchybar clock popup hover-exit behavior is covered"
