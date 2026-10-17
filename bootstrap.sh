#!/usr/bin/env bash
# Bootstrap a fresh Mac for this dotfiles-manager checkout.
# Idempotent: safe to re-run. First run only; routine applies use `just sync-dfm`.
set -euo pipefail

# Resolve the physical checkout path. When bootstrap is invoked through the
# ~/.dotfiles symlink, plain `pwd` preserves that logical path and can otherwise
# replace the link with a self-reference (`~/.dotfiles -> ~/.dotfiles`).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Map the machine's LocalHostName to a profile name. The matcher list is
# shared across every host-resolving script; add machines in
# scripts/host-detect.sh only.
# shellcheck source=scripts/host-detect.sh
source "${REPO_ROOT}/scripts/host-detect.sh"

# ── 0. Xcode Command Line Tools ──────────────────────────────────────────
# Homebrew and native builds need them first. Idempotent: no-op if already installed/accepted.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Installing Xcode Command Line Tools ..."
  xcode-select --install || true
  echo "    Finish the GUI installer, then re-run ./bootstrap.sh."
  exit 0
fi
sudo xcodebuild -license accept 2>/dev/null || true

# ── 1. Resolve host profile (arg > LocalHostName map > prompt) ───────────
HOST="${1:-$(detect_host || true)}"
if [ -z "${HOST:-}" ]; then
  echo "Could not auto-detect host from LocalHostName."
  read -r -p "Enter host profile (personal-mac): " HOST
fi
if [ ! -f "$REPO_ROOT/dfm/profiles/$HOST.toml" ]; then
  echo "error: no profile at dfm/profiles/$HOST.toml" >&2
  exit 1
fi
echo "==> Using host profile: $HOST"

# ── 2. ~/.dotfiles symlink (the root every managed link resolves through) ─
if [ "$REPO_ROOT" = "$HOME/.dotfiles" ]; then
  # The repository itself is already checked out at the canonical location.
  :
elif [ "$(readlink "$HOME/.dotfiles" 2>/dev/null || true)" != "$REPO_ROOT" ]; then
  echo "==> Linking $HOME/.dotfiles -> $REPO_ROOT"
  ln -sfn "$REPO_ROOT" "$HOME/.dotfiles"
fi

# ── 3. Homebrew and the Brewfile ─────────────────────────────────────────
# DOTFILES_BREW_BIN is for test isolation; runtime scripts require /opt/homebrew.
BREW_BIN="${DOTFILES_BREW_BIN:-/opt/homebrew/bin/brew}"
if [ ! -x "$BREW_BIN" ]; then
  echo "==> Installing Homebrew ..."
  # Download separately so set -e catches curl failures.
  # An explicit XXXXXX template works with both BSD and GNU mktemp.
  brew_install_sh="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_install_sh"
  NONINTERACTIVE=1 /bin/bash "$brew_install_sh"
  rm -f "$brew_install_sh"
else
  echo "==> Homebrew already installed: $("$BREW_BIN" --version | head -1)"
fi
# brew is not on PATH in a fresh login shell yet.
eval "$("$BREW_BIN" shellenv)" 2>/dev/null || true
echo "==> Installing the Brewfile (just, mise, uv and the rest) ..."
"$REPO_ROOT/scripts/brew-sync.sh"

# ── 4. rustup ────────────────────────────────────────────────────────────
# The manager's installer builds from a pinned Rust toolchain staged out of
# ~/.rustup (docs/m5-cutover.md section 1). Nothing in the Brewfile installs rustup.
if ! command -v rustup >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  echo "==> Installing rustup ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
fi

# ── 5. dotfiles-manager ──────────────────────────────────────────────────
# The manager is installed from its own repository (docs/m5-cutover.md section 1).
# It is not a Homebrew package, so this script stops here and prints the steps.
echo
echo "==> Done. Remaining steps:"
if command -v dotfiles-manager >/dev/null 2>&1; then
  echo "    dotfiles-manager is installed: $(command -v dotfiles-manager)"
else
  echo "    1. Stage the pinned Rust toolchain and install dotfiles-manager from its"
  echo "       repository: docs/m5-cutover.md section 1 names the toolchain version,"
  echo "       the staging copy and the commit to install."
fi
if [ -e "$HOME/.config/dotfiles-manager/machine.toml" ]; then
  echo "    This machine is bound: $HOME/.config/dotfiles-manager/machine.toml"
else
  echo "    2. Bind this machine to its profile (plan needs a binding):"
  echo "       dotfiles-manager bind --profile $HOME/.dotfiles/dfm/profiles/$HOST.toml --machine-id <id>"
fi
echo "    3. just sync-dfm                      # plan; writes the approval flags"
echo "    4. just sync-dfm-apply <plan digest>  # apply, packages, side channels, agents, checks"
echo "    Side channels that need network or SSH (secrets, agent-registry, token-auditor)"
echo "    run inside step 4, or alone with 'just sync-side-channels'."
echo
echo "    Manual first-run steps (TCC-protected, cannot be scripted):"
echo "      - Accessibility → Display → Reduce transparency"
echo "      - Keyboard → Modifier Keys → remap Caps Lock"
echo "      - Privacy & Security → Accessibility: grant AeroSpace + SketchyBar"
