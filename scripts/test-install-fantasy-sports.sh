#!/usr/bin/env bash
# install-fantasy-sports.sh copies agents and the Cursor skill from a working copy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/src/agents/fantasy-football-manager" \
  "$fixture/src/skills/fantasy-football-guidelines"
printf '%s\n' '---' 'name: fantasy-football-manager' '---' 'body' \
  >"$fixture/src/agents/fantasy-football-manager/agent.md"
printf '%s\n' '---' 'name: fantasy-football-guidelines' '---' '# skill' \
  >"$fixture/src/skills/fantasy-football-guidelines/SKILL.md"

cat >"$fixture/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$TEST_COMMAND_LOG"
exit 1
EOF
chmod +x "$fixture/git"

TEST_COMMAND_LOG="$fixture/commands.log" \
  HOME="$fixture/home" \
  GIT_BIN="$fixture/git" \
  FANTASY_SPORTS_WORKING_COPY="$fixture/src" \
  FANTASY_SPORTS_MANAGED_COPY="$fixture/should-not-clone" \
  "$repo_root/scripts/install-fantasy-sports.sh"

for path in \
  "$fixture/home/.claude/agents/fantasy-football-manager.md" \
  "$fixture/home/.cursor/agents/fantasy-football-manager.md" \
  "$fixture/home/.config/opencode/agents/fantasy-football-manager.md" \
  "$fixture/home/.cursor/skills/fantasy-football-guidelines/SKILL.md"; do
  if [ ! -f "$path" ]; then
    echo "missing installed file: $path" >&2
    exit 1
  fi
done

if [ -s "$fixture/commands.log" ]; then
  echo "working copy install cloned or fetched a remote" >&2
  exit 1
fi
if [ -e "$fixture/should-not-clone" ]; then
  echo "working copy install created a managed clone" >&2
  exit 1
fi

echo "install-fantasy-sports: OK"
