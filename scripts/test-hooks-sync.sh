#!/usr/bin/env bash
# hooks-sync.sh --check must print the plan and write nothing under HOME.
# A normal run with a stubbed uv must merge the hippo hook once and replace the symlink.
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

tree_hash() {
  (cd "$home" && find . -mindepth 1 -print0 | sort -z |
    while IFS= read -r -d '' f; do
      if [[ -L $f ]]; then printf 'L %s %s\n' "$f" "$(readlink "$f")"
      elif [[ -f $f ]]; then printf 'F %s %s\n' "$f" "$(shasum <"$f")"
      else printf 'D %s\n' "$f"; fi
    done | shasum)
}

before="$(tree_hash)"
out="$(HOME="$home" DFM_REPO_ROOT="$repo_root" "$repo_root/scripts/hooks-sync.sh" --check 2>&1)"
[[ $before == "$(tree_hash)" ]] || { echo "--check wrote under the fixture" >&2; exit 1; }
[[ -L $home/.codex/hooks.json ]] || { echo "--check replaced the hooks symlink" >&2; exit 1; }
for want in "would run (MCP sync)" "would run (skill sync)" "would merge the hippo SessionStart hook"; do
  [[ $out == *"$want"* ]] || { echo "missing in --check output: $want" >&2; printf '%s\n' "$out" >&2; exit 1; }
done

printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/uv"
chmod +x "$fixture/uv"
for _ in 1 2; do
  HOME="$home" DFM_REPO_ROOT="$repo_root" UV_BIN="$fixture/uv" "$repo_root/scripts/hooks-sync.sh" >/dev/null 2>&1
done
[[ -f $home/.codex/hooks.json && ! -L $home/.codex/hooks.json ]] || { echo "hooks.json is not a regular file" >&2; exit 1; }
count="$(jq '[.hooks.SessionStart[]?.hooks[]?.command | select(endswith("claude-session-hook.sh"))] | length' "$home/.codex/hooks.json")"
[[ $count == 1 ]] || { echo "expected 1 hippo hook, found $count" >&2; exit 1; }

echo "hooks-sync test passed"
