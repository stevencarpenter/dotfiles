#!/usr/bin/env bash
# Test the Claude settings hook-preservation jq in modules/home/ai-stack.nix.
#
# Proves the property PR #120 added: a merge of the managed block over the live
# ~/.claude/settings.json must PRESERVE hooks a tool self-registered into the
# live file (under any event), while still enforcing managed hooks and sweeping
# stale/capability-off managed hooks. The jq is extracted verbatim from
# ai-stack.nix between the `# hooks-merge-jq:begin/end` sentinels, so this test
# always exercises the exact program the activation runs — no drift-prone copy.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix="$repo/modules/home/ai-stack.nix"

JQ="$(awk '/# hooks-merge-jq:begin/{f=1} f{print} /# hooks-merge-jq:end/{f=0}' "$nix")"
[ -n "$JQ" ] || { echo "FAIL: could not extract hooks-merge jq from $nix" >&2; exit 1; }

pass=0 fail=0
check() { # name  got  want
  if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; pass=$((pass + 1))
  else printf '  FAIL %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
merge() { printf '%s\n' "$2" | jq --argjson managed "$1" "$JQ"; }

echo "scenario 1: personal host (hippo + routing on)"
managed='{"hooks":{"SessionStart":[
  {"hooks":[{"type":"command","command":"/Users/x/.local/share/hippo-brain/shell/claude-session-hook.sh"}]},
  {"hooks":[{"type":"command","command":"/Users/x/.claude/hooks/emit-routing-context.sh"}]}
]}}'
# live: the managed hippo hook (dup), a FOREIGN SessionStart hook, a STALE
# hippo-marker hook (changed path), and foreign command/non-command handlers.
live='{"hooks":{
  "SessionStart":[
    {"hooks":[{"type":"command","command":"/Users/x/.local/share/hippo-brain/shell/claude-session-hook.sh"}]},
    {"hooks":[{"type":"command","command":"/opt/herdr/agent-state.sh"}]},
    {"hooks":[{"type":"command","command":"/Users/x/.local/share/hippo-brain/OLD-session-hook.sh"}]}
  ],
  "PreToolUse":[{"matcher":"Write","hooks":[
    {"type":"command","command":"/opt/herdr/pre.sh"},
    {"type":"prompt","prompt":"Review this write"},
    {"type":"agent","prompt":"Validate this write"},
    {"type":"http","url":"https://localhost/hook"},
    {"type":"mcp_tool","server":"guard","tool":"check","input":{"path":"x"}}
  ]}]
}}'
out="$(merge "$managed" "$live")"
check "foreign SessionStart hook survives" \
  "$(jq -c '[.hooks.SessionStart[].hooks[].command]|any(.=="/opt/herdr/agent-state.sh")' <<<"$out")" true
check "foreign PreToolUse hook survives" \
  "$(jq -c '[.hooks.PreToolUse[].hooks[].command]|any(.=="/opt/herdr/pre.sh")' <<<"$out")" true
check "all non-command hook types survive" \
  "$(jq -r '[.hooks.PreToolUse[].hooks[].type] | sort | join(",")' <<<"$out")" \
  "agent,command,http,mcp_tool,prompt"
check "foreign hook-group metadata survives" \
  "$(jq -r '.hooks.PreToolUse[0].matcher' <<<"$out")" Write
check "managed hippo hook present exactly once" \
  "$(jq -c '[.hooks.SessionStart[].hooks[].command|select(endswith("shell/claude-session-hook.sh"))]|length' <<<"$out")" 1
check "stale hippo-marker hook swept" \
  "$(jq -c '[.hooks.SessionStart[].hooks[].command]|any(contains("OLD-session-hook.sh"))' <<<"$out")" false

echo "scenario 2: work host (both SessionStart capabilities off -> managed has no hooks)"
managed='{}'
# live carries a stale hippo hook (capability now off) and a foreign hook.
live='{"hooks":{"SessionStart":[
  {"hooks":[{"type":"command","command":"/Users/x/.local/share/hippo-brain/shell/claude-session-hook.sh"}]},
  {"hooks":[{"type":"command","command":"/opt/herdr/agent-state.sh"}]}
]}}'
out="$(merge "$managed" "$live")"
check "capability-off hippo hook swept" \
  "$(jq -c '[.hooks.SessionStart[]?.hooks[].command]|any(contains("hippo-brain"))' <<<"$out")" false
check "foreign hook still survives when managed has no hooks" \
  "$(jq -c '[.hooks.SessionStart[]?.hooks[].command]|any(.=="/opt/herdr/agent-state.sh")' <<<"$out")" true

echo "scenario 3: stale and retired managed commands are swept"
managed='{"hooks":{"WorktreeCreate":[
  {"hooks":[{"type":"command","command":"~/.claude/hooks/wt-create.sh"}]}
]}}'
live='{"hooks":{
  "WorktreeCreate":[
    {"hooks":[{"type":"command","command":"/Users/x/.claude/hooks/wt-create.sh"}]}
  ],
  "PreToolUse":[{"hooks":[{"type":"command","command":"Edit encrypted_* via chezmoi add --encrypt"}]}],
  "PostToolUse":[{"hooks":[{"type":"command","command":"chezmoi execute-template < file"}]}]
}}'
out="$(merge "$managed" "$live")"
check "path-equivalent managed hook is not duplicated" \
  "$(jq -c '[.hooks.WorktreeCreate[].hooks[].command] | length' <<<"$out")" 1
check "retired encrypted-file hook is swept" \
  "$(jq -c '[.hooks.PreToolUse[]?.hooks[].command] | length' <<<"$out")" 0
check "retired template hook is swept" \
  "$(jq -c '[.hooks.PostToolUse[]?.hooks[].command] | length' <<<"$out")" 0

echo
echo "hooks-preservation: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
