#!/usr/bin/env bash
# macOS `defaults` — source of truth for intentional user tweaks.
#
# Chezmoi re-runs this whenever the file hash changes, so edit a value and
# `chezmoi apply` re-asserts it across all machines. Everything here uses
# Apple-supported `defaults` keys (same ones System Settings writes), so
# SOC-locked machines won't flag it.
#
# Layout:
#   1. General / UI        — Dark mode, key repeat, press-and-hold
#   2. Dock                — autohide delay, orientation, size, hot corners
#   3. Finder              — view style, desktop items, sidebar
#   4. Screenshots         — location, thumbnail behavior
#   5. Menu bar clock      — date/weekday (SketchyBar owns time display)
#   6. Trackpad            — tap-to-click, gestures, three-finger drag
#   7. Activity Monitor    — default category
#
# Not managed here (TCC-protected, requires manual one-time setup in System
# Settings):
#   - Accessibility → Display → Reduce transparency
#   - Keyboard → Keyboard Shortcuts → Modifier Keys (Caps Lock remap)
#   - Privacy & Security → Accessibility (AeroSpace, SketchyBar accessibility)
#
# After writing, this script restarts Dock / Finder / SystemUIServer so the
# changes apply immediately. Anything requiring logout (rare) is noted inline.
set -euo pipefail

# ─── 1. General / UI ──────────────────────────────────────────────────────────

# Dark mode
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Disable press-and-hold-for-accents (keeps vim-style key repeat working in
# every text field — accents via option+e, option+u, etc. if needed).
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Fast key repeat. InitialKeyRepeat is pre-repeat delay (lower = faster start),
# KeyRepeat is inter-repeat interval (lower = faster repeat). Apple's minimum
# sliders stop at 15 / 2.
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2

# Text substitutions: keep capitalization + period-on-double-space, drop the
# rest. We leave quote/dash/spelling substitution alone (default behavior).
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true

# Trackpad pointer speed (0.0–3.0 visible in Settings; 1.5 is mid-high).
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 1.5

# ─── 2. Dock ──────────────────────────────────────────────────────────────────

# Auto-hide on, with a deliberately slow pop-in to prevent edge misclicks
# against AeroSpace-tiled windows.
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1.0
defaults write com.apple.dock autohide-time-modifier -float 0.6

# Vertical dock on the left, small tiles.
defaults write com.apple.dock orientation -string "left"
defaults write com.apple.dock tilesize -int 40

# Hot corners. Codes: 1=disabled, 2=Mission Control, 3=App Windows, 4=Desktop,
# 5=Start Screen Saver, 6=Disable Screen Saver, 7=Dashboard (gone), 10=Put
# Display to Sleep, 11=Launchpad, 12=Notification Center, 13=Lock Screen,
# 14=Quick Note. Modifiers are bitmasks: shift=131072, ctrl=262144, opt=524288,
# cmd=1048576; 0 = no modifier required.
defaults write com.apple.dock wvous-br-corner -int 14     # Quick Note
defaults write com.apple.dock wvous-br-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 13     # Lock Screen
defaults write com.apple.dock wvous-tr-modifier -int 0

# ─── 3. Finder ────────────────────────────────────────────────────────────────

# List view as default (Nlsv=list, icnv=icon, clmv=column, glyv=gallery).
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Show sidebar; don't clutter the desktop with internal drives but do surface
# external drives + removable media for quick access.
defaults write com.apple.finder ShowSidebar -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# ─── 4. Screenshots ───────────────────────────────────────────────────────────

# Dedicated folder so Desktop doesn't fill with Screenshot-*.png, no floating
# thumbnail preview (stays out of the way of AeroSpace tiling).
mkdir -p "$HOME/Desktop/screenshots"
defaults write com.apple.screencapture location -string "$HOME/Desktop/screenshots"
defaults write com.apple.screencapture show-thumbnail -bool false

# ─── 5. Menu Bar Clock ────────────────────────────────────────────────────────

# SketchyBar owns the primary clock display; the native menubar clock just
# needs to not compete. Weekday shown, date hidden.
defaults write com.apple.menuextra.clock ShowDate -int 0
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

# ─── 6. Trackpad ──────────────────────────────────────────────────────────────

# Tap-to-click OFF (both internal and paired Bluetooth trackpads). Physical
# click only — reduces accidental clicks during typing.
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool false

# Three-finger drag OFF (conflicts with AeroSpace-style workflows; use click
# + drag instead).
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false

# Four-finger swipes = Mission Control / Spaces navigation (value 2 = enabled).
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 2

# ─── 7. Activity Monitor ──────────────────────────────────────────────────────

# ShowCategory=100 = "All Processes" (0=My Processes, 100=All, 101=All,
# Hierarchically, 102=System, 103=Other User, 104=Active, 105=Inactive,
# 106=Windowed, 107=Selected Processes, 108=Apps in last 8 hours).
defaults write com.apple.ActivityMonitor ShowCategory -int 100

# ─── Apply changes ────────────────────────────────────────────────────────────

for app in Dock Finder SystemUIServer cfprefsd; do
  killall "$app" 2>/dev/null || true
done

echo "macOS defaults applied."
