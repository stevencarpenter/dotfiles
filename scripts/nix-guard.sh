#!/usr/bin/env bash
# Refuse to run nix on a machine that dotfiles-manager owns (DFM-52).
# A nix switch recreates org.nixos.maxfiles and the Home Manager links.
# Set DFM_ALLOW_NIX=1 only for a deliberate rollback (docs/m5-cutover.md section 11).
# Source or exec this from every nix entry point: the just recipes, rebuild.sh,
# bootstrap.sh and the zsh rebuild function.
set -euo pipefail

if [[ -e "${HOME}/.config/dotfiles-manager/machine.toml" && "${DFM_ALLOW_NIX:-}" != 1 ]]; then
  echo "error: dotfiles-manager owns this machine. A nix switch recreates org.nixos.maxfiles and the Home Manager links." >&2
  echo "Set DFM_ALLOW_NIX=1 only for a rollback (docs/m5-cutover.md section 11)." >&2
  exit 1
fi
