#!/usr/bin/env bash
# Port of the Home Manager sync hooks that no manager resource covers.
# Usage: hooks-sync.sh [--check]
#   (none)   run mcpSync, skillsSync, codexHooksMerge in Home Manager order
#   --check  print what would run; write nothing
# Each step warns and continues on failure, like the nix activation hooks.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
identity="${DFM_IDENTITY:-personal}"
uv_bin="${UV_BIN:-uv}"
jq_bin="${JQ_BIN:-jq}"
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
  # sync-skills runs git and ssh as subprocesses; /usr/bin matches the nix hook's explicit git and ssh.
  PATH="/usr/bin:$PATH" run_py "skill sync" mcp_sync.skills_cli --repo-root "$canonical" --machine-config "$overlay"
}

# Add the hippo SessionStart hook without replacing other hooks. A symlinked
# hooks.json becomes a real file so the codebase-memory-mcp installer can write it.
codex_hooks_merge() {
  local hooks="$HOME/.codex/hooks.json"
  local hippo="$HOME/.local/share/hippo-brain/shell/claude-session-hook.sh"
  local content merged tmp
  echo "==> codexHooksMerge"
  if ((check)); then
    echo "would merge the hippo SessionStart hook into $hooks"
    [[ -L $hooks ]] && echo "would replace the symlink $hooks with a real file first"
    return 0
  fi
  command -v "$jq_bin" >/dev/null 2>&1 || { echo "Warning: jq not found; skipping Codex hooks merge." >&2; return 0; }
  mkdir -p "$HOME/.codex" || return 0
  if [[ -L $hooks ]]; then
    content="$(cat "$hooks" 2>/dev/null || printf '{"hooks":{}}')"
    rm -f "$hooks"
    printf '%s' "$content" >"$hooks"
  fi
  [[ -f $hooks ]] || printf '{"hooks":{}}' >"$hooks"
  # shellcheck disable=SC2016 # $cmd is a jq variable
  if merged="$("$jq_bin" --arg cmd "$hippo" '
        .hooks //= {} |
        if ([.hooks.SessionStart[]?.hooks[]?.command] | index($cmd)) != null then .
        else .hooks.SessionStart = [{hooks: [{type: "command", command: $cmd}]}]
               + (.hooks.SessionStart // [])
        end' "$hooks")"; then
    if [[ -z $merged ]]; then
      echo "Warning: empty hippo hook merge result for $hooks; leaving it alone." >&2
      return 0
    fi
    tmp="$(mktemp "$hooks.XXXXXX")" || return 0
    chmod 600 "$tmp"
    printf '%s\n' "$merged" >"$tmp"
    mv "$tmp" "$hooks" || rm -f "$tmp"
  else
    echo "Warning: could not merge hippo hook into $hooks; leaving it alone." >&2
  fi
}

mcp_sync
skills_sync
[[ $identity == personal ]] && codex_hooks_merge
exit 0
