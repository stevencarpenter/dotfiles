#!/usr/bin/env bash
# Rebuild this machine's nix-darwin + home-manager configuration.
# Auto-detects the flake config from LocalHostName; override with an arg:
#   ./rebuild.sh              # detect host, switch
#   ./rebuild.sh work-mac     # force a specific host config
set -euo pipefail

# Resolve the physical checkout path. Lix 2.94 rejects a symlink as a flake
# root, even though ~/.dotfiles remains the stable path for out-of-store links.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "$(realpath "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  echo "error: $HOME/.dotfiles does not resolve to $REPO_ROOT; run bootstrap.sh to repair it" >&2
  exit 1
fi

# Map LocalHostName to a flake config name. Tune the matchers per box.
detect_host() {
  case "$(scutil --get LocalHostName 2>/dev/null || true)" in
    personal-mac) echo personal-mac ;;
    work-mac) echo work-mac ;;
    *) return 1 ;;
  esac
}

HOST="${1:-$(detect_host || true)}"
if [ -z "${HOST:-}" ]; then
  echo "unknown host; pass explicitly: rebuild.sh <personal-mac|work-mac>" >&2
  exit 1
fi

exec sudo darwin-rebuild switch --flake "$REPO_ROOT#${HOST}"
