#!/usr/bin/env bash
# Sync steps that no dfm resource covers.
# Usage: hooks-sync.sh [--check]
#   (none)   run mcpSync, then skillsSync
#   --check  print what would run; write nothing
# Each step warns and continues on failure.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# The identity comes from the host's profile; DFM_IDENTITY is a test seam.
if [[ -z ${DFM_IDENTITY:-} ]] && ! DFM_IDENTITY="$("$repo_root/scripts/host-capability.sh" --identity)"; then
  echo "error: cannot resolve the host identity; set DOTFILES_HOST or DFM_IDENTITY" >&2
  exit 2
fi
identity="$DFM_IDENTITY"
uv_bin="${UV_BIN:-uv}"
# Skill links must stay stable, so prefer the canonical checkout over a worktree.
if [[ -z ${DFM_REPO_ROOT:-} && -d $HOME/.dotfiles/mcp_sync ]]; then
  canonical="$HOME/.dotfiles"
else
  canonical="${DFM_REPO_ROOT:-$repo_root}"
fi
project="$canonical/mcp_sync"

check=0
case "${1:-}" in
  "") ;;
  --check) check=1 ;;
  *) echo "usage: hooks-sync.sh [--check]" >&2; exit 2 ;;
esac

# run_py <label> <module> [args...]: uv-managed python, no user site, source on PYTHONPATH.
run_py() {
  local label="$1"; shift
  if ((check)); then
    echo "would run ($label): uv run --project $project python -m $*"
    return 0
  fi
  PYTHONNOUSERSITE=1 PYTHONPATH="$project/src" \
    "$uv_bin" run --frozen --no-dev --project "$project" python -m "$@" ||
    echo "Warning: $label failed." >&2
}

mcp_sync() {
  local overlay="$HOME/.config/mcp/machine/$identity.json"
  [[ -f $project/pyproject.toml ]] || { echo "Warning: MCP sync project not found at $project; skipping." >&2; return 0; }
  [[ -f $overlay ]] || { echo "Warning: no machine overlay at $overlay; skipping MCP sync." >&2; return 0; }
  echo "==> mcpSync"
  run_py "MCP sync" mcp_sync --machine-config "$overlay"
}

skills_sync() {
  local overlay="$HOME/.config/skills/machine/$identity.json"
  [[ -f $project/pyproject.toml ]] || { echo "Warning: skill sync project not found at $project; skipping." >&2; return 0; }
  [[ -f $overlay ]] || { echo "Warning: no machine overlay at $overlay; skipping skill sync." >&2; return 0; }
  echo "==> skillsSync"
  # sync-skills runs git and ssh as subprocesses; pin them to the system binaries.
  PATH="/usr/bin:$PATH" run_py "skill sync" mcp_sync.skills_cli --repo-root "$canonical" --machine-config "$overlay"
}

mcp_sync
skills_sync
exit 0
