#!/usr/bin/env bash
# Validate the repository-managed Pi configuration without contacting npm.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
settings="${repo_root}/home/.pi/agent/settings.json"
theme="${repo_root}/home/.pi/agent/themes/everforest-dark-hard.json"

jq empty "${settings}"
jq empty "${theme}"

jq -e '
  (.packages | type == "array") and
  all(.packages[]; test("^npm:(@[^/]+/)?[^@/]+@[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.theme == "everforest-dark-hard") and
  (.defaultModel | type == "string" and length > 0) and
  (.modelThinkingLevels["openai/gpt-5.6-luna"] == "xhigh")
' "${settings}" >/dev/null

jq -e '
  (.name == "everforest-dark-hard") and
  (.colors | type == "object") and
  (.colors | has("accent") and has("text") and has("muted") and has("error") and has("success"))
' "${theme}" >/dev/null

while IFS= read -r color; do
  case "${color}" in
    \#*) ;;
    *) jq -e --arg name "${color}" '.vars | has($name)' "${theme}" >/dev/null ;;
  esac
done < <(jq -r '.colors[]' "${theme}")

echo "test-pi-config: OK (pinned packages and validated theme references)"
