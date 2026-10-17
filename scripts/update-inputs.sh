#!/usr/bin/env bash
# Preview Homebrew and mise upgrades, then apply them and run the side channels after approval.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

assume_yes=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    -h|--help)
      echo "Usage: just update [-y|--yes]"
      echo "Preview Homebrew and mise updates, then approve, upgrade and run the side channels."
      exit 0 ;;
    *) echo "update: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
echo "==> Homebrew upgrades (installed, unpinned packages)"
just brew-upgrade --dry-run
export HOMEBREW_NO_AUTO_UPDATE=1
echo "==> Mise upgrades (within configured version constraints)"
mise install --dry-run
mise upgrade --dry-run --no-prune
echo "==> After approval: upgrade Homebrew, then run the side channels."
echo "Side channels update mise, render secrets, and refresh upstream skills, Git sources, agents, and pinned tools."
echo "Sync also queues Firstmate's native update; Firstmate reports its completion asynchronously."
echo "Exact pins remain fixed. Applied upgrades cannot be automatically undone."

if [ "$assume_yes" -eq 0 ]; then
  reply=""
  read -r -p "Apply these updates and run the side channels? [y/N] " reply || true
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Update cancelled."; exit 0 ;;
  esac
fi

brew upgrade --yes
"$REPO_ROOT/scripts/sync-side-channels.sh"
echo "==> Package update and side channels complete; queued application updates finish asynchronously."
