#!/usr/bin/env bash
# Tests for scripts/check-agent-tools-allowlist.py — the gate that fails a sync
# when a registry-installed Claude agent lost its MCP/skill access.
# Plain-shell convention (no bats). Everything runs against a tmp agents dir;
# the real ~/.claude/agents is never read.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$here/scripts/check-agent-tools-allowlist.py"

fails=0
run() { local name="$1"; shift; if "$@"; then echo "ok   - $name"; else echo "FAIL - $name"; fails=$((fails + 1)); fi; }

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

agent() {
  # agent <dir> <name> <tools-line>
  printf -- '---\nname: %s\n%s\nmodel: inherit\n---\n\nbody\n' "$2" "$3" >"$1/$2.md"
}

manifest() {
  # manifest <dir> <name>...
  local dir="$1"; shift
  local out="[" sep=""
  for n in "$@"; do out+="$sep\"$n.md\""; sep=", "; done
  printf '%s]\n' "$out" >"$dir/.installed-by-agent-registry.json"
}

# The interpreter: run the script directly so its PEP 723 shebang is exercised
# the way install-agent-registry.sh invokes it.
check() { "$CHECK" "$@"; }

# 1. A registry agent with only built-in tools still fails.
d="$work/a"; mkdir -p "$d"
agent "$d" registry-builtin "tools: Read, Bash, Grep"
manifest "$d" registry-builtin
test_builtin_fails() {
  local out; out="$(check "$d" 2>&1)"; local rc=$?
  [ "$rc" -eq 1 ] && grep -q "registry-builtin.md:3" <<<"$out"
}
run "built-in-only registry agent fails" test_builtin_fails

# 2. A third-party plugin agent in the same directory is ignored: it is not in
#    the manifest, and its built-in-only tools line is its own design.
d="$work/b"; mkdir -p "$d"
agent "$d" registry-ok "tools: Read, mcp__hippo__ask"
agent "$d" impeccable-documenter "tools: Read, Write, Bash, Glob, Grep"
manifest "$d" registry-ok
test_plugin_ignored() {
  local out; out="$(check "$d" 2>&1)"; local rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]
}
run "unmanifested plugin agent is not checked" test_plugin_ignored

# 3. The block-sequence tools form is still parsed (regression guard).
d="$work/c"; mkdir -p "$d"
printf -- '---\nname: blockform\ntools:\n  - Read\n  - Bash\n---\n\nbody\n' >"$d/blockform.md"
manifest "$d" blockform
test_block_form() { check "$d" >/dev/null 2>&1; [ "$?" -eq 1 ]; }
run "block-sequence tools list is parsed" test_block_form

# 4. A missing manifest is an error, not a silent pass: the installer always
#    writes one, so its absence means the install did not complete.
d="$work/d"; mkdir -p "$d"
agent "$d" orphan "tools: Read, Bash"
test_missing_manifest() {
  local out; out="$(check "$d" 2>&1)"; local rc=$?
  [ "$rc" -eq 1 ] && grep -q "cannot read agent manifest" <<<"$out"
}
run "missing manifest fails loudly" test_missing_manifest

# 5. A manifest naming a file that is not on disk fails: the registry claimed
#    to install it, so a gap is a broken install rather than a foreign file.
d="$work/e"; mkdir -p "$d"
manifest "$d" vanished
test_missing_agent() {
  local out; out="$(check "$d" 2>&1)"; local rc=$?
  [ "$rc" -eq 1 ] && grep -q "vanished.md: cannot read" <<<"$out"
}
run "manifest entry missing from disk fails" test_missing_agent

# 6. An explicit manifest path outside the agents dir is honored.
d="$work/f"; mkdir -p "$d"
agent "$d" registry-builtin "tools: Read, Bash"
printf '["registry-builtin.md"]\n' >"$work/f-manifest.json"
test_explicit_manifest() { check "$d" "$work/f-manifest.json" >/dev/null 2>&1; [ "$?" -eq 1 ]; }
run "explicit manifest path is honored" test_explicit_manifest

# 7. Bad usage is distinguishable from a violation.
test_usage() { check >/dev/null 2>&1; [ "$?" -eq 2 ]; }
run "no arguments exits 2" test_usage

if [ "$fails" -ne 0 ]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all agent tools allowlist tests passed"
