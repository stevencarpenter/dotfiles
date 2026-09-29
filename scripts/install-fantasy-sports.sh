#!/usr/bin/env bash
# Install the private fantasy-sports agents and Cursor skill copy.
#
# Claude/pi skills are fanned out by mcp_sync from skills-master.json. This
# script owns harness surfaces mcp_sync does not: Claude/Cursor/OpenCode
# agent files, and the Cursor skill tree. Prefer the working copy, then the
# mcp_sync git cache, then a managed clone.
set -euo pipefail

git_bin="${GIT_BIN:-git}"
remote="${FANTASY_SPORTS_REMOTE:-git@github.com:stevencarpenter/fantasy-sports.git}"
working_copy="${FANTASY_SPORTS_WORKING_COPY:-$HOME/projects/fantasy-sports}"
managed_copy="${FANTASY_SPORTS_MANAGED_COPY:-$HOME/.local/share/fantasy-sports}"
mcp_cache="${FANTASY_SPORTS_MCP_CACHE:-$HOME/.cache/mcp-sync/skills/fantasy-sports}"
agent_name="fantasy-football-manager"
skill_name="fantasy-football-guidelines"

repo_has_agents() {
  [ -f "$1/agents/${agent_name}/agent.md" ]
}

resolve_repo() {
  if repo_has_agents "$working_copy"; then
    printf '%s\n' "$working_copy"
    return 0
  fi
  if repo_has_agents "$mcp_cache"; then
    printf '%s\n' "$mcp_cache"
    return 0
  fi
  if [ -d "$managed_copy/.git" ]; then
    echo "==> Refreshing fantasy-sports" >&2
    "$git_bin" -C "$managed_copy" pull --ff-only
  else
    echo "==> Cloning fantasy-sports (SSH)" >&2
    mkdir -p "$(dirname "$managed_copy")"
    "$git_bin" clone "$remote" "$managed_copy"
  fi
  printf '%s\n' "$managed_copy"
}

repo="$(resolve_repo)"
agent_src="$repo/agents/${agent_name}/agent.md"
skill_src="$repo/skills/${skill_name}"

if [ ! -f "$agent_src" ]; then
  echo "warning: fantasy-sports agent missing at $agent_src; skipping agent install" >&2
  exit 0
fi

echo "==> Installing fantasy-sports agents from $repo"
agent_file="${agent_name}.md"
for dest in \
  "$HOME/.claude/agents" \
  "$HOME/.cursor/agents" \
  "$HOME/.config/opencode/agents"; do
  mkdir -p "$dest"
  cp "$agent_src" "$dest/$agent_file"
done

if [ -f "$skill_src/SKILL.md" ]; then
  echo "==> Installing fantasy-sports Cursor skill from $repo"
  cursor_skill="$HOME/.cursor/skills/${skill_name}"
  mkdir -p "$HOME/.cursor/skills"
  rm -rf "$cursor_skill"
  cp -R "$skill_src" "$cursor_skill"
fi
