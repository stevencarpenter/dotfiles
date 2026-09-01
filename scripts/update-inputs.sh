#!/usr/bin/env bash
# Advance every rolling pin this repo is meant to move by default: the 26.05
# flake inputs together, the nixpkgs-unstable soak queue, and Homebrew.
#
# Never switches. Review the lock/Brewfile diff, then apply with `just sync`.
# Extra args are forwarded to scripts/update-unstable.sh (soak days, host).
#
# The unstable input is a rev pin. Do not `nix flake update` it here — only
# scripts/update-unstable.sh may move that node.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

echo "==> Updating nixpkgs, nix-darwin, and home-manager (26.05 line)"
nix flake update nixpkgs nix-darwin home-manager

echo "==> Advancing the nixpkgs-unstable soak queue"
"${REPO_ROOT}/scripts/update-unstable.sh" "$@"

echo "==> Upgrading Homebrew bundle"
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
brew update
brew bundle install --upgrade

echo
echo "==> Updated, not switched. Review the diff, then apply with:"
echo "      just sync"
git --no-pager diff --stat -- flake.lock flake.nix versions/nixpkgs-unstable-candidate.json || true
