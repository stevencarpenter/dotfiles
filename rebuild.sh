#!/usr/bin/env bash
# Rebuild this machine's nix-darwin + home-manager configuration.
# Auto-detects the flake config from LocalHostName; override with an arg:
#   ./rebuild.sh              # detect host, switch
#   ./rebuild.sh personal-mac # force a specific host config
set -euo pipefail

# Resolve the physical checkout path. Lix 2.94 rejects a symlink as a flake
# root, even though ~/.dotfiles remains the stable path for out-of-store links.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "$(realpath "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
	echo "error: $HOME/.dotfiles does not resolve to $REPO_ROOT; run bootstrap.sh to repair it" >&2
	exit 1
fi

# Map LocalHostName to a flake config name. The matcher list is shared across
# every host-resolving script; add machines in scripts/host-detect.sh only.
# shellcheck source=scripts/host-detect.sh
source "${REPO_ROOT}/scripts/host-detect.sh"

# $DOTFILES_HOST is the same override scripts/host-capability.sh honors; accept
# it here too so an explicitly-hosted deploy resolves identically on both sides
# of `just sync` instead of the switch failing while the side channels succeed.
HOST="${1:-${DOTFILES_HOST:-$(detect_host || true)}}"
if [ -z "${HOST:-}" ]; then
	echo "unknown host; pass explicitly: rebuild.sh <personal-mac>" >&2
	exit 1
fi

# Surface a due nixpkgs-unstable promotion at the moment of a rebuild (see
# scripts/unstable-reminder.sh). Best-effort by contract: never blocks.
if [ -x "${REPO_ROOT}/scripts/unstable-reminder.sh" ]; then
	"${REPO_ROOT}/scripts/unstable-reminder.sh" || true
fi

# Pass the declared macOS 27 compatibility setting as a build flag too. This
# recovers a machine whose currently-running daemon still has sandbox=true:
# the new nix.conf cannot be built unless the trusted rebuild request disables
# that broken sandbox first.
exec sudo darwin-rebuild switch \
	--flake "$REPO_ROOT#${HOST}" \
	--option sandbox false
