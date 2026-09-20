#!/usr/bin/env bash
# Validate configuration shape, npm pins, and theme references, not preferences.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
settings="${repo_root}/home/.pi/agent/settings.json"

jq -e '
  def nonempty_string: type == "string" and length > 0;
  # Pi also accepts local paths, Git sources, and objects with resource filters.
  # Only npm sources use npm version syntax; never require local files in CI.
  def package_source:
    if type == "object" then .source else . end;
  (.packages | type == "array") and
  all(.packages[]; package_source | nonempty_string and
    (if startswith("npm:") then
      test("^npm:(@[^/]+/)?[^@/]+@[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$")
    else true end)) and
  all(.theme, .defaultModel, .defaultProvider; . == null or nonempty_string) and
  (if has("defaultThinkingLevel") then .defaultThinkingLevel | nonempty_string else true end) and
  (if has("modelThinkingLevels") then
    .modelThinkingLevels | type == "object" and all(.[]; nonempty_string)
  else true end)
' "${settings}" >/dev/null || {
  echo "${settings}: invalid settings shape or npm source without an exact version pin" >&2
  exit 1
}

shopt -s nullglob
for theme in "${repo_root}/home/.pi/agent/themes/"*.json; do
  jq -e --arg name "$(basename "${theme}" .json)" '
    (.name == $name) and
    (.colors | type == "object") and
    (.colors | has("accent") and has("text") and has("muted") and has("error") and has("success")) and
    (.vars as $vars | all(.colors[]; startswith("#") or (. as $color | $vars | has($color))))
  ' "${theme}" >/dev/null || {
    echo "${theme}: invalid theme name, required colors, or color variable reference" >&2
    exit 1
  }
done

echo "test-pi-config: OK (pinned npm packages and validated theme references)"
