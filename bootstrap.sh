#!/usr/bin/env bash
# Bootstrap a fresh Mac into the nix-darwin + home-manager dotfiles flake.
# Idempotent: safe to re-run. First run only — routine rebuilds use rebuild.sh.
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
# anything native. Idempotent — no-op if already installed/accepted.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Installing Xcode Command Line Tools ..."
  xcode-select --install || true
  echo "    Finish the GUI installer, then re-run ./bootstrap.sh."
  exit 0
fi
sudo xcodebuild -license accept 2>/dev/null || true

# ── 1. Lix ───────────────────────────────────────────────────────────────
# nix.enable = true + nix.package = pkgs.lix in modules/darwin/core.nix —
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

# ── 3. (removed) age identity key ────────────────────────────────────────
# This repo declares zero age.secrets on every identity, so no host needs an
# age identity. All secrets here render from 1Password via op-render; secrets
# for an externally-owned host are that wrapper's custody, fetched by its own
# bootstrap. Bootstrap must never write ~/.config/age/keys.txt.

# ── 4. ~/.dotfiles symlink (out-of-store root for raw dotfiles) ───────────
if [ "$REPO_ROOT" = "$HOME/.dotfiles" ]; then
  # The repository itself is already checked out at the canonical location.
  :
elif [ "$(readlink "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  echo "==> Linking $HOME/.dotfiles -> $REPO_ROOT"
  ln -sfn "$REPO_ROOT" "$HOME/.dotfiles"
fi

# ── 4.5 Homebrew (independent install; nix references but does not own it) ──
# nix-darwin's homebrew module runs `brew bundle` during activation, so brew
# must exist BEFORE the first switch. This replaced nix-homebrew, whose
# brew-src pin froze brew at a patched 6.0.1 while homebrew-core moved on.
#
# DOTFILES_BREW_BIN is a test seam, NOT a relocation knob — modules/darwin/
# homebrew.nix and modules/home/tiling.nix hardcode /opt/homebrew. It exists so
# scripts/test-bootstrap-clt-gate.sh can drive both branches hermetically: an
# absolute path is invisible to that harness's PATH-based stubbing, so on any
# host without brew (i.e. every Linux CI runner) bootstrap would otherwise
# download and execute the real Homebrew installer in the middle of the test.
BREW_BIN="${DOTFILES_BREW_BIN:-/opt/homebrew/bin/brew}"
if [ ! -x "$BREW_BIN" ]; then
  echo "==> Installing Homebrew (independent of nix) ..."
  # Download to a file first: in `bash -c "$(curl …)"` a curl failure is
  # swallowed (the substitution's exit status is lost) and bootstrap would
  # continue with no brew installed. Under set -e this aborts instead.
  # Explicit XXXXXX template rather than `-t homebrew-install`: BSD mktemp
  # treats -t's argument as a prefix and appends randomness, but GNU mktemp
  # rejects it ("too few X's in template"), and the hygiene test runs this
  # script on a Linux runner. Same accommodation as perm() in that test.
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

# ── 6. rustup (dev toolchain) ────────────────────────────────────────────
# Kept as an imperative bootstrap rather than a nixpkgs toolchain: rustup's
# toolchain-switching workflow differs from a pinned nix toolchain, and that
# behavior change was deliberately NOT applied during the port. Idempotent —
# no-op if rustup already present.
if ! command -v rustup >/dev/null 2>&1; then
  echo "==> Installing rustup ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
fi

# ── 7. Network/SSH side channels ─────────────────────────────────────────
# The switch in step 5 just created these profiles, but THIS shell's PATH was
# computed before they existed — so on a fresh machine the `command -v just`
# guard below always failed and the whole side channel (tpm, agent-registry,
# token-auditor) silently never provisioned. Prepend the profiles rather than
# resolving `just` alone: scripts/sync-side-channels.sh needs `git` too, and
# hard-exits 1 when `uv` is not on PATH.
PATH="/etc/profiles/per-user/$(id -un)/bin:/run/current-system/sw/bin:$PATH"
export PATH
JUST_BIN="${DOTFILES_JUST_BIN:-just}"

# Side channels only — NOT `just sync`, which now begins with its own
# darwin-rebuild switch. Step 5 above already switched this host, and `just
# sync` forwards no host to rebuild.sh, so on a fresh machine whose
# LocalHostName is not yet in the detect_host map (exactly the case the $HOST
# argument exists to handle) the nested rebuild would exit 1 and the `||` below
# would swallow it — silently skipping tpm, the agent registry, token-auditor,
# and op-render.
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
