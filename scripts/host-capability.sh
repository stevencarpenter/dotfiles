#!/usr/bin/env bash
# Read one host capability (or --identity) from lib/machines.nix, the gating source of truth.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capability="${1:-}"

# Shared LocalHostName matcher (single place to add a machine).
# shellcheck source=scripts/host-detect.sh
source "${repo_root}/scripts/host-detect.sh"

# `--identity` prints the host's identity string instead of a 0/1 capability.
# identity is a peer of caps in lib/machines.nix (some gates are
# `optionalAttrs (identity == "…")`, not `mkIf caps.x`), so callers outside nix
# need to read it from the same source of truth rather than re-detecting.
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

case "$host" in
  personal-mac) ;;
  *)
    if [ "$mode" = identity ]; then
      echo "error: cannot resolve a known host for --identity" >&2
    else
      echo "error: cannot resolve a known host for capability '$capability'" >&2
    fi
    exit 2
    ;;
esac

# Parse the static table without nix. nix is absent after the M5 cutover
# (DFM-52), and lib/machines.nix stays the gating source of truth until DFM-42
# retires it; this reader must move to the DFM profile at that point.
# nixfmt keeps the table as one `key = value;` per line inside `  <host> = {`.
machines="${repo_root}/lib/machines.nix"
block="$(awk -v host="$host" '
  $0 == "  " host " = {" { inblock = 1 }
  inblock { print }
  inblock && $0 == "  };" { exit }
' "$machines")"

if [ "$mode" = identity ]; then
  value="$(printf '%s\n' "$block" | awk '$1 == "identity" && $2 == "=" { gsub(/[";]/, "", $3); print $3; exit }')"
  if [ -z "$value" ]; then
    echo "error: no identity for host '$host' in lib/machines.nix" >&2
    exit 2
  fi
  printf '%s' "$value"
  exit 0
fi

value="$(printf '%s\n' "$block" | awk -v key="$capability" '$1 == key && $2 == "=" { sub(/;$/, "", $3); print $3; exit }')"
case "$value" in
  true) printf '1' ;;
  false) printf '0' ;;
  *)
    echo "error: capability '$capability' is not declared for host '$host' in lib/machines.nix" >&2
    exit 2
    ;;
esac
