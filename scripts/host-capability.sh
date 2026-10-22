#!/usr/bin/env bash
# Read one host capability (or --identity) from the host's dfm profile, the gating source of truth.
# The profile is dfm/profiles/<host>.toml when a host is named (argument or DOTFILES_HOST),
# else the profile `dfm binding` names (it may live in an external bundle's checkout),
# else dfm/profiles/<detected host>.toml for a machine that is not bound yet.
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

bound_profile() { # the profile path `dfm binding` prints; nothing when dfm is absent or unbound
  local dfm_bin="${DFM_BIN:-dfm}"
  command -v "$dfm_bin" >/dev/null 2>&1 || return 0
  { "$dfm_bin" binding 2>/dev/null || true; } |
    sed -n 's/^bound profile=\(.*\) machine_id=.*$/\1/p' | tail -1
}

profile=""
if [ -z "$host" ]; then
  profile="$(bound_profile)"
  if [ -n "$profile" ] && [ ! -f "$profile" ]; then
    echo "error: the bound profile $profile does not exist" >&2
    exit 2
  fi
fi

if [ -z "$profile" ]; then
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
fi

# shortcut: the profile keeps `modules = [...]` on one line, switch to a TOML parser
# when a profile needs a multi-line list. Until then a multi-line or missing list is an
# error: reading it as empty would turn every gate off without a failure.
if ! awk -F'[][]' '$1 ~ /^modules[[:space:]]*=[[:space:]]*$/ { found = 1; one_line = NF >= 3; exit }
  END { exit !(found && one_line) }' "$profile"; then
  echo "error: $profile needs a one-line modules = [...] list" >&2
  exit 2
fi
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
