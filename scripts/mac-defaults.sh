#!/usr/bin/env bash
# macOS defaults for the personal MacBook.
#
# Usage: mac-defaults.sh [--check | --no-restart]
#   --check       Read every key, print ok / differs / unset. Exit 1 if any differs
#                 or is unset. Never writes.
#   (default)     Write only the differing keys, create the screenshots directory and
#                 the .metadata_never_index sentinels, then restart Dock.
#   --no-restart  Default mode without the Dock restart.
#
# setting                                     domain                                    key                                   type    value
# NSGlobalDomain.AppleInterfaceStyle          NSGlobalDomain                             AppleInterfaceStyle                   string  Dark
# NSGlobalDomain.ApplePressAndHoldEnabled     NSGlobalDomain                             ApplePressAndHoldEnabled              bool    false
# NSGlobalDomain.InitialKeyRepeat             NSGlobalDomain                             InitialKeyRepeat                      int     15
# NSGlobalDomain.KeyRepeat                    NSGlobalDomain                             KeyRepeat                             int     2
# NSGlobalDomain.NSAutomaticCapitalizationEnabled        NSGlobalDomain                  NSAutomaticCapitalizationEnabled      bool    true
# NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled    NSGlobalDomain                  NSAutomaticPeriodSubstitutionEnabled  bool    true
# NSGlobalDomain."com.apple.trackpad.scaling" NSGlobalDomain                             com.apple.trackpad.scaling            float   1.5
# menuExtraClock.ShowDate                     com.apple.menuextra.clock                  ShowDate                              int     0
# menuExtraClock.ShowDayOfWeek                com.apple.menuextra.clock                  ShowDayOfWeek                         bool    true
# dock.autohide                               com.apple.dock                             autohide                              bool    true
# dock.autohide-delay                         com.apple.dock                             autohide-delay                        float   1.0
# dock.autohide-time-modifier                 com.apple.dock                             autohide-time-modifier                float   0.6
# dock.orientation                            com.apple.dock                             orientation                           string  left
# dock.tilesize                               com.apple.dock                             tilesize                              int     40
# finder.FXPreferredViewStyle                 com.apple.finder                           FXPreferredViewStyle                  string  Nlsv
# finder.ShowExternalHardDrivesOnDesktop      com.apple.finder                           ShowExternalHardDrivesOnDesktop       bool    true
# finder.ShowHardDrivesOnDesktop              com.apple.finder                           ShowHardDrivesOnDesktop               bool    false
# finder.ShowRemovableMediaOnDesktop          com.apple.finder                           ShowRemovableMediaOnDesktop           bool    true
# CustomUserPreferences."com.apple.finder".ShowSidebar  com.apple.finder                 ShowSidebar                           bool    true
# screencapture.location                      com.apple.screencapture                    location                              string  ~/Desktop/screenshots (absolute)
# screencapture.show-thumbnail                com.apple.screencapture                    show-thumbnail                        bool    false
# trackpad.Clicking                           com.apple.AppleMultitouchTrackpad          Clicking                              bool    false
# trackpad.TrackpadThreeFingerDrag            com.apple.AppleMultitouchTrackpad          TrackpadThreeFingerDrag               bool    false
# trackpad.TrackpadFourFingerHorizSwipeGesture com.apple.AppleMultitouchTrackpad         TrackpadFourFingerHorizSwipeGesture   int     2
# trackpad.TrackpadFourFingerVertSwipeGesture  com.apple.AppleMultitouchTrackpad        TrackpadFourFingerVertSwipeGesture    int     2
# trackpad.* (same four keys, written to both domains)
#                                             com.apple.driver.AppleBluetoothMultitouch.trackpad   (same keys and values)
# ActivityMonitor.ShowCategory                com.apple.ActivityMonitor                  ShowCategory                          int     100
#
# Files (postActivation): ~/Desktop/screenshots, and .metadata_never_index in ~/projects and ~/programs.
# Only Dock is restarted; Finder and SystemUIServer are not.
set -euo pipefail

mode=apply restart=1
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  --no-restart) restart=0 ;;
  *) echo "usage: $0 [--check | --no-restart]" >&2; exit 2 ;;
esac

shot="$HOME/Desktop/screenshots"
rows=()
add() { rows+=("$1|$2|$3|$4"); }
for kv in AppleInterfaceStyle:string:Dark ApplePressAndHoldEnabled:bool:false InitialKeyRepeat:int:15 \
  KeyRepeat:int:2 NSAutomaticCapitalizationEnabled:bool:true NSAutomaticPeriodSubstitutionEnabled:bool:true \
  com.apple.trackpad.scaling:float:1.5; do
  IFS=: read -r k t v <<<"$kv"; add NSGlobalDomain "$k" "$t" "$v"
done
add com.apple.menuextra.clock ShowDate int 0
add com.apple.menuextra.clock ShowDayOfWeek bool true
add com.apple.dock autohide bool true
add com.apple.dock autohide-delay float 1.0
add com.apple.dock autohide-time-modifier float 0.6
add com.apple.dock orientation string left
add com.apple.dock tilesize int 40
add com.apple.finder FXPreferredViewStyle string Nlsv
add com.apple.finder ShowExternalHardDrivesOnDesktop bool true
add com.apple.finder ShowHardDrivesOnDesktop bool false
add com.apple.finder ShowRemovableMediaOnDesktop bool true
add com.apple.finder ShowSidebar bool true
add com.apple.screencapture location string "$shot"
add com.apple.screencapture show-thumbnail bool false
for d in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
  add "$d" Clicking bool false
  add "$d" TrackpadThreeFingerDrag bool false
  add "$d" TrackpadFourFingerHorizSwipeGesture int 2
  add "$d" TrackpadFourFingerVertSwipeGesture int 2
done
add com.apple.ActivityMonitor ShowCategory int 100

# Print the live value normalised to the want format; empty output means unset.
live_value() {
  local v
  v=$(defaults read "$1" "$2" 2>/dev/null) || return 0
  printf '%s' "$v"
}

same() { # type live want
  case "$1" in
    bool) [[ "$2" == "$([[ "$3" == true ]] && echo 1 || echo 0)" ]] ;;
    float) awk -v a="$2" -v b="$3" 'BEGIN{exit !(a+0==b+0)}' ;;
    *) [[ "$2" == "$3" ]] ;;
  esac
}

differ=0 unset_n=0 written=0
for row in "${rows[@]}"; do
  IFS='|' read -r dom key type want <<<"$row"
  live=$(live_value "$dom" "$key")
  if [[ -z "$live" ]]; then
    state='unset'
  elif same "$type" "$live" "$want"; then
    state=ok
  else
    state=differs
  fi
  if [[ $mode == check ]]; then
    case "$state" in
      ok) printf 'ok      %s %s = %s\n' "$dom" "$key" "$want" ;;
      differs) printf 'differs %s %s: live %s, want %s\n' "$dom" "$key" "$live" "$want"; differ=1 ;;
      unset) printf 'unset   %s %s: want %s\n' "$dom" "$key" "$want"; unset_n=$((unset_n + 1)) ;;
    esac
  elif [[ $state != ok ]]; then
    defaults write "$dom" "$key" "-$type" "$want"
    echo "wrote $dom $key = $want"
    written=$((written + 1))
  fi
done

sentinels=("$HOME/projects/.metadata_never_index" "$HOME/programs/.metadata_never_index")
if [[ $mode == check ]]; then
  if [[ -d $shot ]]; then echo "ok      dir $shot"; else echo "differs dir $shot: missing"; differ=1; fi
  for s in "${sentinels[@]}"; do
    if [[ -e $s ]]; then echo "ok      file $s"; else echo "differs file $s: missing"; differ=1; fi
  done
  [[ $unset_n -gt 0 ]] && differ=1
  exit "$differ"
fi

mkdir -p "$shot"
for s in "${sentinels[@]}"; do
  mkdir -p "$(dirname "$s")"
  touch "$s"
done
if [[ $restart -eq 1 && $written -gt 0 ]]; then
  killall -q Dock || true
fi
echo "mac-defaults: $written key(s) written"
