#!/usr/bin/env bash
# Read one host capability (or --identity) from dfm/profiles/<host>.toml, the gating source of truth.
# A capability is on when the profile selects the module of the same name (`_` becomes `-`).
# A capability is known when dfm-bundle.toml declares that module.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capability="${1:-}"

# Shared LocalHostName matcher (single place to add a machine).
# shellcheck source=scripts/host-detect.sh
source "${repo_root}/scripts/host-detect.sh"

# `--identity` prints the host's identity string instead of a 0/1 capability.
# The identity is the selected module named personal, work or lab.
mode=capability
if [ "$capability" = "--identity" ]; then
  mode=identity
  shift
fi
host="${2:-${DOTFILES_HOST:-}}"
[ "$mode" = identity ] && host="${1:-${DOTFILES_HOST:-}}"

if [ "$mode" = capability ] && [[ ! "$capability" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "error: invalid or missing capability name" >&2
  exit 2
fi

if [ -z "$host" ]; then
  host="$(detect_host || true)"
fi

profile="${repo_root}/dfm/profiles/${host}.toml"
if [ -z "$host" ] || [[ ! "$host" =~ ^[a-z0-9-]+$ ]] || [ ! -f "$profile" ]; then
  if [ "$mode" = identity ]; then
    echo "error: cannot resolve a known host for --identity" >&2
  else
    echo "error: cannot resolve a known host for capability '$capability'" >&2
  fi
  exit 2
fi

# shortcut: the profile keeps `modules = [...]` on one line, switch to a TOML parser
# when a profile needs a multi-line list.
selected="$(awk -F'[][]' '$1 ~ /^modules[[:space:]]*=[[:space:]]*$/ {
  gsub(/["[:space:]]/, "", $2); gsub(/,/, " ", $2); print $2; exit }' "$profile")"
declared="$(awk '/^\[modules\]/ { f = 1; next } /^\[/ { f = 0 } f && /^[a-z-]+[[:space:]]*=/ {
  sub(/[[:space:]]*=.*/, ""); print }' "${repo_root}/dfm-bundle.toml")"

has_word() { # has_word <word> <space-separated list>
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

if [ "$mode" = identity ]; then
  for module in $selected; do
    case "$module" in
      personal | work | lab) printf '%s' "$module"; exit 0 ;;
    esac
  done
  echo "error: no identity module (personal, work or lab) selected in $profile" >&2
  exit 2
fi

module="${capability//_/-}"
if ! has_word "$module" "$(printf '%s' "$declared" | tr '\n' ' ')"; then
  echo "error: capability '$capability' is not a module in dfm-bundle.toml" >&2
  exit 2
fi
if has_word "$module" "$selected"; then printf '1'; else printf '0'; fi
