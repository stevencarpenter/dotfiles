#!/usr/bin/env bash
# Evaluate one host capability from lib/machines.nix (the gating source of truth).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capability="${1:-}"
host="${2:-${DOTFILES_HOST:-}}"

if [[ ! "$capability" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "error: invalid or missing capability name" >&2
  exit 2
fi

if [ -z "$host" ]; then
  case "$(scutil --get LocalHostName 2>/dev/null || true)" in
    personal-mac | Stevens-MacBook-Pro) host=personal-mac ;;
    work-mac) host=work-mac ;;
  esac
fi

case "$host" in
  personal-mac | work-mac) ;;
  *)
    echo "error: cannot resolve a known host for capability '$capability'" >&2
    exit 2
    ;;
esac

nix_bin="${NIX_BIN:-nix}"
exec "$nix_bin" eval --impure --raw --expr "
  let
    machines = import ${repo_root}/lib/machines.nix;
    host = machines.${host};
  in
    if host.caps.${capability} then \"1\" else \"0\"
"
