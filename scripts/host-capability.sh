#!/usr/bin/env bash
# Evaluate one host capability from lib/machines.nix (the gating source of truth).
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

nix_bin="${NIX_BIN:-nix}"

if [ "$mode" = identity ]; then
  exec "$nix_bin" eval --impure --raw --expr "
    let
      machines = import ${repo_root}/lib/machines.nix;
    in
      machines.${host}.identity
  "
fi

exec "$nix_bin" eval --impure --raw --expr "
  let
    machines = import ${repo_root}/lib/machines.nix;
    host = machines.${host};
  in
    if host.caps.${capability} then \"1\" else \"0\"
"
