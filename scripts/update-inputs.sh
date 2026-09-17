#!/usr/bin/env bash
# Preview rolling package updates, then reuse sync to deploy after approval.
# Exact pins and the unstable first-seen soak policy remain authoritative.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

assume_yes=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    -h|--help)
      echo "Usage: just update [-y|--yes] [SOAK_DAYS [HOST]]"
      echo "Preview Nix, Homebrew, and mise updates, then approve and deploy via sync."
      exit 0 ;;
    -*) echo "update: unknown option: $arg" >&2; exit 2 ;;
    *) positional+=("$arg") ;;
  esac
done
soak_days="${positional[0]:-1}"
if [ "${#positional[@]}" -gt 2 ] || ! [[ "$soak_days" =~ ^[0-9]{1,4}$ ]] || ((10#$soak_days > 3650)); then
  echo "update: expected soak days 0-3650 and an optional host" >&2
  exit 2
fi
soak_days=$((10#$soak_days))
# shellcheck source=scripts/host-detect.sh
source "$REPO_ROOT/scripts/host-detect.sh"
host="${positional[1]:-${DOTFILES_HOST:-$(detect_host || true)}}"
if ! [[ "$host" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "update: missing or invalid host; use just update 1 <host>" >&2
  exit 2
fi

# Preserve pre-existing edits too. Declining or failing preparation restores
# these exact files, not HEAD. Once applying starts, retain the reviewed inputs.
backup="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-update.XXXXXX")"
inputs=(flake.nix flake.lock versions/nixpkgs-unstable-candidate.json)
for file in "${inputs[@]}"; do
  if [ -f "$file" ]; then
    mkdir -p "$backup/$(dirname "$file")"
    cp -p "$file" "$backup/$file"
  fi
done
applying=0
finish() {
  local status=$?
  if [ "$applying" -eq 0 ]; then
    for file in "${inputs[@]}"; do
      if [ -f "$backup/$file" ]; then
        cp -p "$backup/$file" "$file"
      else
        rm -f -- "$file"
      fi
    done
    echo "Nix input files restored; no package upgrades or system switch applied."
  elif [ "$status" -ne 0 ]; then
    echo "Update stopped during apply. Some steps may have completed; reviewed Nix inputs retained." >&2
  fi
  rm -rf -- "$backup"
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "==> Preparing Nix inputs (26.05 line; unstable soak: $soak_days days)"
nix flake update nixpkgs nix-darwin home-manager
"$REPO_ROOT/scripts/update-unstable.sh" "$soak_days" "$host"
nix flake check --no-update-lock-file --no-build --all-systems
out="$(nix build --no-link --print-out-paths --no-update-lock-file \
  --option sandbox false ".#darwinConfigurations.${host}.system")"
echo "==> Nix package changes"
nix store diff-closures /run/current-system "$out"
echo "==> Nix input changes from before this update"
for file in "${inputs[@]}"; do
  before="$backup/$file"
  [ -f "$before" ] || before=/dev/null
  diff -u "$before" "$file" || [ "$?" -eq 1 ]
done

export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
echo "==> Homebrew upgrades (installed, unpinned packages)"
just brew-upgrade --dry-run
export HOMEBREW_NO_AUTO_UPDATE=1
echo "==> Mise upgrades (within configured version constraints)"
mise install --dry-run
mise upgrade --dry-run --no-prune
echo "==> After approval: upgrade Homebrew, then run just sync $host."
echo "Sync switches Nix, updates mise, renders secrets, and refreshes Git sources, agents, and pinned tools."
echo "Exact pins remain fixed. Preview downloads/builds are cached. Applied upgrades cannot be automatically undone."

if [ "$assume_yes" -eq 0 ]; then
  reply=""
  read -r -p "Apply these updates and sync? [y/N] " reply || true
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Update cancelled."; exit 0 ;;
  esac
fi

applying=1
brew upgrade --yes
just sync "$host"
echo "==> Update and sync complete."
