#!/usr/bin/env bash
# Bootstrap a fresh Mac into the nix-darwin + home-manager dotfiles flake.
# Idempotent: safe to re-run. First run only — routine rebuilds use rebuild.sh.
set -euo pipefail

# Resolve the physical checkout path. When bootstrap is invoked through the
# ~/.dotfiles symlink, plain `pwd` preserves that logical path and can otherwise
# replace the link with a self-reference (`~/.dotfiles -> ~/.dotfiles`).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Map the machine's LocalHostName to a flake config name. Tune the matchers per
# box as machines are added to lib/machines.nix.
detect_host() {
  case "$(scutil --get LocalHostName 2>/dev/null || true)" in
    personal-mac | Stevens-MacBook-Pro) echo personal-mac ;;
    work-mac) echo work-mac ;;
    *) return 1 ;;
  esac
}

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
  read -r -p "Enter host config (personal-mac / work-mac): " HOST
fi
echo "==> Using host config: $HOST"

# ── 3. Work-only age identity key from 1Password ─────────────────────────
# Personal secrets are rendered directly from 1Password and declare zero
# age.secrets. The carry-verbatim age bridge remains work-only until the
# external work wrapper takes custody of those secrets.
if [ "$HOST" = "work-mac" ]; then
  KEY_DEST="$HOME/.config/age/keys.txt"
  if [ ! -s "$KEY_DEST" ]; then
    echo "==> Fetching work age identity key from 1Password ..."
    if ! command -v op >/dev/null 2>&1; then
      echo "ERROR: 1Password CLI (op) not found. Install it, sign in, then re-run." >&2
      exit 1
    fi
    mkdir -p "$(dirname "$KEY_DEST")"
    op read "op://Private/dotfiles-age-key/notesPlain" >"$KEY_DEST"
    chmod 600 "$KEY_DEST"
  else
    echo "==> work age key already present at $KEY_DEST"
  fi
fi

# ── 4. ~/.dotfiles symlink (out-of-store root for raw dotfiles) ───────────
if [ "$REPO_ROOT" = "$HOME/.dotfiles" ]; then
  # The repository itself is already checked out at the canonical location.
  :
elif [ "$(readlink "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  echo "==> Linking $HOME/.dotfiles -> $REPO_ROOT"
  ln -sfn "$REPO_ROOT" "$HOME/.dotfiles"
fi

# ── 5. First switch ──────────────────────────────────────────────────────
# darwin-rebuild is not on PATH yet, so run it straight from the flake input.
echo "==> Building initial configuration #$HOST ..."
# --extra-experimental-features so this first switch does not depend on the
# Lix installer's default nix.conf having flakes enabled; nix-darwin pins them
# in nix.settings from here on.
sudo nix run \
  --extra-experimental-features "nix-command flakes" \
  github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$REPO_ROOT#${HOST}"

# ── 6. rustup (dev toolchain) ────────────────────────────────────────────
# Kept as an imperative bootstrap rather than a nixpkgs toolchain: rustup's
# toolchain-switching workflow differs from a pinned nix toolchain, and that
# behavior change was deliberately NOT applied during the port (see
# docs/nix-migration.md). Idempotent — no-op if rustup already present.
if ! command -v rustup >/dev/null 2>&1; then
  echo "==> Installing rustup ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
fi

# ── 7. Network/SSH side channels ─────────────────────────────────────────
echo "==> Running 'just sync' for git externals + token-auditor ..."
if command -v just >/dev/null 2>&1; then
  DOTFILES_HOST="$HOST" just sync \
    || echo "    (just sync had warnings; re-run later once online/authed)"
else
  echo "    'just' not on PATH yet; run 'just sync' after the switch completes."
fi

echo
echo "==> Done. Subsequent rebuilds: ./rebuild.sh (or the 'rebuild' shell fn)."
echo "    Provisioning that needs network/SSH (agent-registry, token-auditor,"
echo "    tpm) runs via 'just sync'."
echo
echo "    Manual first-run steps (TCC-protected, cannot be scripted):"
echo "      - Accessibility → Display → Reduce transparency"
echo "      - Keyboard → Modifier Keys → remap Caps Lock"
echo "      - Privacy & Security → Accessibility: grant AeroSpace + SketchyBar"
