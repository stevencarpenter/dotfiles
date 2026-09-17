#!/usr/bin/env bash
# Validate configuration shape, package pins, and theme references, not preferences.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
settings="${repo_root}/home/.pi/agent/settings.json"

jq -e '
  def nonempty_string: type == "string" and length > 0;
  (.packages | type == "array") and
  all(.packages[]; test("^npm:(@[^/]+/)?[^@/]+@[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  all(.theme, .defaultModel, .defaultProvider; . == null or nonempty_string) and
  (if has("defaultThinkingLevel") then .defaultThinkingLevel | nonempty_string else true end) and
  (if has("modelThinkingLevels") then
    .modelThinkingLevels | type == "object" and all(.[]; nonempty_string)
  else true end)
' "${settings}" >/dev/null

shopt -s nullglob
for theme in "${repo_root}/home/.pi/agent/themes/"*.json; do
  jq -e --arg name "$(basename "${theme}" .json)" '
    (.name == $name) and
    (.colors | type == "object") and
    (.colors | has("accent") and has("text") and has("muted") and has("error") and has("success")) and
    (.vars as $vars | all(.colors[]; startswith("#") or (. as $color | $vars | has($color))))
  ' "${theme}" >/dev/null
done

echo "test-pi-config: OK (pinned packages and validated theme references)"
