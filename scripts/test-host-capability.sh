#!/usr/bin/env bash
# Assert that scripts/host-capability.sh reads lib/machines.nix without nix.
# After the M5 cutover (DFM-52) nix is absent, so the reader must not exec it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

# An empty PATH entry that holds no nix proves the script never execs it.
nonix="$(mktemp -d)"
trap 'rm -rf "$nonix"' EXIT
export PATH="$nonix:/usr/bin:/bin"
export DOTFILES_HOST=personal-mac

fail() { echo "FAIL: $*" >&2; exit 1; }

[ "$(scripts/host-capability.sh --identity)" = personal ] || fail "identity"
[ "$(scripts/host-capability.sh mcp)" = 1 ] || fail "mcp should be 1"
[ "$(scripts/host-capability.sh infra)" = 0 ] || fail "infra should be 0"
[ "$(scripts/host-capability.sh agents)" = 1 ] || fail "agents should be 1"
[ "$(scripts/host-capability.sh skills)" = 1 ] || fail "skills should be 1"

# Undeclared capability and unknown host both exit 2 with an error.
if scripts/host-capability.sh bogus 2>/dev/null; then fail "bogus should exit 2"; fi
if scripts/host-capability.sh mcp no-such-host 2>/dev/null; then fail "unknown host should exit 2"; fi
if scripts/host-capability.sh 'bad name' 2>/dev/null; then fail "invalid name should exit 2"; fi

echo "ok: host-capability.sh resolves personal-mac without nix"
