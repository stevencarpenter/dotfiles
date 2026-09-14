#!/usr/bin/env bash
# Bootstrap a fresh Mac into the nix-darwin + home-manager dotfiles flake.
# Idempotent: safe to re-run. First run only; routine rebuilds use rebuild.sh.
set -euo pipefail

# Resolve the physical checkout path. When bootstrap is invoked through the
# ~/.dotfiles symlink, plain `pwd` preserves that logical path and can otherwise
# replace the link with a self-reference (`~/.dotfiles -> ~/.dotfiles`).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Map the machine's LocalHostName to a flake config name. The matcher list is
# shared across every host-resolving script; add machines in
# scripts/host-detect.sh only.
# shellcheck source=scripts/host-detect.sh
source "${REPO_ROOT}/scripts/host-detect.sh"

# ── 0. Xcode Command Line Tools ──────────────────────────────────────────
# nix-darwin has no option for CLT; they must exist before nix can build
# anything native. Idempotent: no-op if already installed/accepted.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Installing Xcode Command Line Tools ..."
  xcode-select --install || true
  echo "    Finish the GUI installer, then re-run ./bootstrap.sh."
  exit 0
fi
sudo xcodebuild -license accept 2>/dev/null || true

# ── 1. Lix ───────────────────────────────────────────────────────────────
# nix.enable = true + nix.package = pkgs.lix in modules/darwin/core.nix:
# nix-darwin manages the daemon, Lix is the interpreter. The nix-darwin
# prerequisites recommend the Lix installer because it ships an uninstaller
# (`/nix/nix-installer uninstall`); the upstream installer does not.
if ! command -v nix >/dev/null 2>&1; then
  echo "==> Installing Lix ..."
  curl -sSf -L https://install.lix.systems/lix | sh -s -- install
  # Load nix into THIS shell so the first switch below can run.
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
else
  echo "==> Nix already installed: $(command -v nix)"
fi

# ── 2. Resolve host config (arg > LocalHostName map > prompt) ─────────────
HOST="${1:-$(detect_host || true)}"
if [ -z "${HOST:-}" ]; then
  echo "Could not auto-detect host from LocalHostName."
  read -r -p "Enter host config (personal-mac): " HOST
fi
echo "==> Using host config: $HOST"


# ── 4. ~/.dotfiles symlink (out-of-store root for raw dotfiles) ───────────
if [ "$REPO_ROOT" = "$HOME/.dotfiles" ]; then
  # The repository itself is already checked out at the canonical location.
  :
elif [ "$(readlink "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  echo "==> Linking $HOME/.dotfiles -> $REPO_ROOT"
  ln -sfn "$REPO_ROOT" "$HOME/.dotfiles"
fi

# Install Homebrew before nix-darwin runs brew bundle during activation.
# DOTFILES_BREW_BIN is for test isolation; runtime modules require /opt/homebrew.
BREW_BIN="${DOTFILES_BREW_BIN:-/opt/homebrew/bin/brew}"
if [ ! -x "$BREW_BIN" ]; then
  echo "==> Installing Homebrew (independent of nix) ..."
  # Download separately so set -e catches curl failures.
  # An explicit XXXXXX template works with both BSD and GNU mktemp.
  brew_install_sh="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_install_sh"
  NONINTERACTIVE=1 /bin/bash "$brew_install_sh"
  rm -f "$brew_install_sh"
else
  echo "==> Homebrew already installed: $("$BREW_BIN" --version | head -1)"
fi

# ── 5. First switch ──────────────────────────────────────────────────────
# darwin-rebuild is not on PATH yet, so run it straight from the flake input.
# The nix-darwin BRANCH ref is deliberate for this one-shot context: a fresh
# machine has no trustworthy local lock yet, and the branch tracks the same
# release line flake.nix pins (nix-darwin-26.05). Everything after the first
# switch resolves through this repo's own lockfile instead.
echo "==> Building initial configuration #$HOST ..."
# --extra-experimental-features so this first switch does not depend on the
# Lix installer's default nix.conf having flakes enabled; nix-darwin pins them
# in nix.settings from here on.
sudo nix run \
  --extra-experimental-features "nix-command flakes" \
  github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$REPO_ROOT#${HOST}" \
  --option sandbox false

# rustup manages switchable development toolchains independently of Nix.
if ! command -v rustup >/dev/null 2>&1; then
  echo "==> Installing rustup ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
fi

# Load the new profiles so this shell can resolve just, git, and uv for sync.
PATH="/etc/profiles/per-user/$(id -un)/bin:/run/current-system/sw/bin:$PATH"
export PATH
JUST_BIN="${DOTFILES_JUST_BIN:-just}"

# The host is already switched. Run side channels directly and forward HOST;
# another auto-detected rebuild could select a different host or fail detection.
echo "==> Running side channels for git externals + token-auditor ..."
if command -v "$JUST_BIN" >/dev/null 2>&1; then
  DOTFILES_HOST="$HOST" "$JUST_BIN" --justfile "$REPO_ROOT/Justfile" sync-side-channels \
    || echo "    (side channels had warnings; re-run later once online/authed)"
else
  echo "    'just' not on PATH yet; run 'just sync' once the switch completes."
fi

echo
echo "==> Done. Subsequent rebuilds: ./rebuild.sh (or the 'rebuild' shell fn)."
echo "    Provisioning that needs network/SSH (agent-registry, token-auditor,"
echo "    tpm) runs via 'just sync' (switch + side channels)."
echo
echo "    Manual first-run steps (TCC-protected, cannot be scripted):"
echo "      - Accessibility → Display → Reduce transparency"
echo "      - Keyboard → Modifier Keys → remap Caps Lock"
echo "      - Privacy & Security → Accessibility: grant AeroSpace + SketchyBar"
