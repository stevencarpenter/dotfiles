#!/usr/bin/env bash
# Manage the org.carpenter.maxfiles LaunchAgent (replaces nix launchd.user.agents.maxfiles).
# Usage: launch-agents.sh load | unload | --check
#   load     launchctl bootstrap gui/$UID (no-op when already loaded)
#   unload   launchctl bootout (no-op when not loaded)
#   --check  launchctl print; exit 1 when not loaded. Never writes.
# The plist is linked into ~/Library/LaunchAgents by the dotfiles-manager bundle.
set -euo pipefail

label=org.carpenter.maxfiles
domain="gui/$(id -u)"
plist="$HOME/Library/LaunchAgents/$label.plist"

loaded() { launchctl print "$domain/$label" >/dev/null 2>&1; }

case "${1:-}" in
  --check)
    if loaded; then
      echo "ok: $label loaded in $domain"
    else
      echo "not loaded: $label in $domain"
      # Report the agents nix-darwin or older setups loaded.
      launchctl list | awk '$3 ~ /maxfiles/ {print "other maxfiles agent loaded: " $3}'
      exit 1
    fi
    ;;
  load)
    if loaded; then echo "already loaded: $label"; else
      [[ -e $plist ]] || { echo "missing plist: $plist" >&2; exit 1; }
      launchctl bootstrap "$domain" "$plist"
    fi
    ;;
  unload)
    if loaded; then launchctl bootout "$domain/$label"; else echo "not loaded: $label"; fi
    ;;
  *) echo "usage: $0 load|unload|--check" >&2; exit 2 ;;
esac
