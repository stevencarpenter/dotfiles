#!/usr/bin/env bash
# Rebuild this machine's nix-darwin + home-manager configuration.
# Auto-detects the flake config from LocalHostName; override with an arg:
#   ./rebuild.sh              # detect host, switch
#   ./rebuild.sh work-mac     # force a specific host config
set -euo pipefail

# Keep the out-of-store symlink root fresh (harmless if already correct) so
# raw home/* dotfiles resolve after the repo moves.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(readlink "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  ln -sfn "$REPO_ROOT" "$HOME/.dotfiles"
fi

# Map LocalHostName to a flake config name. Tune the matchers per box.
detect_host() {
  case "$(scutil --get LocalHostName 2>/dev/null || true)" in
    personal-mac) echo personal-mac ;;
    work-mac) echo work-mac ;;
    lab-mac) echo lab-mac ;;
    *) return 1 ;;
  esac
}

HOST="${1:-$(detect_host || true)}"
if [ -z "${HOST:-}" ]; then
  echo "unknown host; pass explicitly: rebuild.sh <personal-mac|work-mac|lab-mac>" >&2
  exit 1
fi

exec sudo darwin-rebuild switch --flake "$HOME/.dotfiles#${HOST}"
