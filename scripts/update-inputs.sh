#!/usr/bin/env bash
# Advance every rolling pin this repo is meant to move by default: the 26.05
# flake inputs together, the nixpkgs-unstable soak queue, and Homebrew.
#
# Never switches the system. The Nix half is staged for review as a lock diff.
# The Homebrew half is NOT: `brew bundle install --upgrade` upgrades installed
# formulae and casks in place, and that has already happened by the time this
# script prints its summary. Only the Nix inputs are reviewable-then-applied.
#
# Extra args are forwarded to scripts/update-unstable.sh (soak days, host).
#
# The unstable input is a rev pin. Do not `nix flake update` it here — only
# scripts/update-unstable.sh may move that node.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

# Validate before mutating anything. update-unstable.sh rejects a bad soak
# window itself, but it runs after `nix flake update`, so an invalid argument
# would otherwise abort the run with the lock already rewritten.
soak_days="${1:-7}"
if ! [[ "${soak_days}" =~ ^[0-9]+$ ]] || ((soak_days > 3650)); then
  echo "update-inputs: soak days must be an integer 0-3650, got '${soak_days}'" >&2
  exit 2
fi

# Report what moved even when a later step fails. Without this a mid-run
# network error leaves a rewritten flake.lock and says nothing about it, which
# is precisely the state a review-before-apply flow must not produce silently.
summarize() {
  echo
  echo "==> Nix inputs updated, not switched. Review the diff, then apply with:"
  echo "      just sync"
  echo "    (Homebrew formulae and casks were already upgraded in place.)"
  git --no-pager diff --stat -- \
    flake.lock flake.nix versions/nixpkgs-unstable-candidate.json
}
trap summarize EXIT

echo "==> Updating nixpkgs, nix-darwin, and home-manager (26.05 line)"
nix flake update nixpkgs nix-darwin home-manager

# Evaluate before recommending a switch. update-unstable.sh builds its own
# promotion, but on a soaking or record-only run it exits without building, so
# nothing would have evaluated the bumped 26.05 inputs until `sudo
# darwin-rebuild switch` was already underway.
echo "==> Checking the updated inputs evaluate"
nix flake check --no-update-lock-file --no-build --all-systems

echo "==> Advancing the nixpkgs-unstable soak queue"
"${REPO_ROOT}/scripts/update-unstable.sh" "$@"

echo "==> Upgrading Homebrew bundle"
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
brew update
brew bundle install --upgrade
