#!/usr/bin/env bash
# hooks-sync.sh --check must print the plan and write nothing under HOME.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
home="$fixture/home"
mkdir -p "$home/.config/mcp/machine" "$home/.config/skills/machine" "$home/.codex"
echo '{}' >"$home/.config/mcp/machine/personal.json"
echo '{}' >"$home/.config/skills/machine/personal.json"
echo '{"hooks":{}}' >"$fixture/real-hooks.json"
ln -s "$fixture/real-hooks.json" "$home/.codex/hooks.json"

before="$(cd "$fixture" && find . -mindepth 1 -exec stat -f '%N %m %z %Sp' {} + | sort)"
out="$(HOME="$home" DFM_REPO_ROOT="$repo_root" "$repo_root/scripts/hooks-sync.sh" --check 2>&1)"
after="$(cd "$fixture" && find . -mindepth 1 -exec stat -f '%N %m %z %Sp' {} + | sort)"

[[ $before == "$after" ]] || { echo "--check wrote under the fixture" >&2; diff <(echo "$before") <(echo "$after") >&2; exit 1; }
[[ -L $home/.codex/hooks.json ]] || { echo "--check replaced the hooks symlink" >&2; exit 1; }
for want in "would run (MCP sync)" "would run (skill sync)" "would merge the hippo SessionStart hook"; do
  [[ $out == *"$want"* ]] || { echo "missing in --check output: $want" >&2; printf '%s\n' "$out" >&2; exit 1; }
done

echo "hooks-sync --check test passed"
