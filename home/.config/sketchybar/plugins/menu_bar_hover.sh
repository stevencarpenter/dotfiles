#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
binary="$cache_dir/sketchybar-menu-hover"
mkdir -p "$cache_dir"

# Reloads replace this helper. Wait for shutdown to restore the bar before starting.
pkill -x sketchybar-menu-hover 2>/dev/null || true
for _ in {1..40}; do
  if ! pgrep -x sketchybar-menu-hover >/dev/null; then
    break
  fi
  sleep 0.05
done
if pgrep -x sketchybar-menu-hover >/dev/null; then
  echo "menu-bar-hover: previous helper did not stop" >&2
  exit 1
fi

if [[ ! -x "$binary" || "$script_dir/menu_bar_hover.swift" -nt "$binary" ]]; then
  build_file="$(mktemp "$cache_dir/menu-hover-build.XXXXXX")"
  trap 'rm -f "$build_file"' EXIT
  /usr/bin/xcrun swiftc -O "$script_dir/menu_bar_hover.swift" -o "$build_file"
  mv "$build_file" "$binary"
fi

bar_pid="$(pgrep -x sketchybar)"
exec "$binary" "$(command -v sketchybar)" "$bar_pid"
