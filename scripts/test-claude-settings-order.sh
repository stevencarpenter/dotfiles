#!/usr/bin/env bash
set -euo pipefail

# Claude settings merge-order regression test (nix shape).
#
# Under chezmoi this rendered dot_claude/modify_settings.json.tmpl via
# `chezmoi execute-template` and drove the resulting modify_ script. The merge
# now lives in modules/home/ai-stack.nix as a home.activation jq pipeline whose
# core step is a recursive merge of the live settings over the managed block:
#     merged = existing * managed        (jq '. * $managed')
# That `*` operator is exactly what preserves the user's existing top-level key
# ordering while appending managed-only keys — the property this test guards.
#
# This test does NOT require nix or chezmoi. It reads the real managed base
# (home/.claude/settings-base.json) and replays the same jq merge semantics
# against a Claude-authored sample, asserting the existing key order survives.
# The capability-varying `variant` slice and the SessionStart strip pass are
# exercised by ai-stack.nix at switch time (verified with jq during the port).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="${repo_root}/home/.claude/settings-base.json"

if [[ ! -f "${base}" ]]; then
  echo "managed base not found at ${base}" >&2
  exit 1
fi

# The base must be valid JSON with the managed structure the module relies on.
jq -e 'type == "object" and has("enabledPlugins") and (.hooks | type == "object")' \
  "${base}" >/dev/null || {
  echo "settings-base.json is not a well-formed managed block" >&2
  exit 1
}

# A Claude-authored settings file: intentionally non-alphabetical, with in-tool
# keys (theme, editorMode, effortLevel) the managed block never sets.
sample_settings=$(cat <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "haiku",
  "theme": "dark",
  "editorMode": "vim",
  "effortLevel": "medium",
  "permissions": {
    "defaultMode": "acceptEdits"
  },
  "teammateMode": "tmux",
  "voiceEnabled": true
}
JSON
)

# Replay ai-stack.nix's core merge: existing * managed.
merged="$(printf '%s\n' "${sample_settings}" | jq --slurpfile managed "${base}" '. * $managed[0]')"

assert_order_preserved() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    {
      echo "${label} key order changed"
      diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") || true
    } >&2
    exit 1
  fi
}

# Every existing top-level key must keep its original position at the front of
# the merged object (managed-only keys are appended after, by jq's `*`).
existing_count="$(printf '%s\n' "${sample_settings}" | jq 'keys_unsorted | length')"
expected_prefix="$(printf '%s\n' "${sample_settings}" | jq -r 'keys_unsorted[]')"
actual_prefix="$(printf '%s\n' "${merged}" | jq -r --argjson n "${existing_count}" 'keys_unsorted[0:$n][]')"
assert_order_preserved "existing top-level" "${expected_prefix}" "${actual_prefix}"

# The user's in-tool-only keys must survive the merge with their values intact.
for key in theme editorMode model; do
  live="$(printf '%s\n' "${sample_settings}" | jq -r --arg k "${key}" '.[$k]')"
  out="$(printf '%s\n' "${merged}" | jq -r --arg k "${key}" '.[$k]')"
  if [[ "${live}" != "${out}" ]]; then
    echo "in-tool key '${key}' was clobbered by the merge (${live} -> ${out})" >&2
    exit 1
  fi
done

# Managed-only keys must be present after the merge (block actually applied).
printf '%s\n' "${merged}" | jq -e 'has("enabledPlugins") and has("extraKnownMarketplaces")' >/dev/null || {
  echo "managed block keys missing after merge" >&2
  exit 1
}

echo "claude settings merge preserves existing key order and in-tool values"
