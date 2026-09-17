#!/usr/bin/env bash
set -euo pipefail

# Verify ai-stack.nix's jq merge preserves existing top-level key order.
# Apply settings-base.json with existing * managed, which appends new keys.
# Also exercise the production normalization/publication block on failures.
# This test excludes capability variants and SessionStart hook stripping.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
base="${fixture}/managed.json"
# Exercise ownership and ordering with synthetic managed keys. Real settings
# may legitimately acquire model, theme, plugin, or other preferences.
printf '%s\n' '{"managedFixtureKey":true,"teammateMode":"tmux"}' >"${base}"

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
  "voiceEnabled": true,
  "sandbox": {"filesystem": {"allowWrite": ["/fixture/user-write"]}}
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
printf '%s\n' "${merged}" | jq -e '.managedFixtureKey == true' >/dev/null || {
  echo "managed block keys missing after merge" >&2
  exit 1
}

echo "claude settings merge preserves existing key order and in-tool values"

# Fragment seam (ai-stack.nix claudeSettingsMerge): a JSON file dropped at
# ~/.claude/settings.d/*.json deep-merges over the managed block BEFORE the
# existing-settings merge above. Replay that fragment loop against a temp
# settings.d holding one fragment that both adds a new key and overrides a
# base scalar key ("teammateMode"), then confirm the same existing*managed
# merge still sees the fragment's values.
fragdir="$(mktemp -d)"
trap 'rm -rf "${fixture}" "${fragdir}"' EXIT

cat >"${fragdir}/01-test.json" <<'JSON'
{
  "testFragmentKey": true,
  "teammateMode": "solo"
}
JSON

managed_with_frag="$(cat "${base}")"
for frag in "${fragdir}"/*.json; do
  [ -f "${frag}" ] || continue
  managed_with_frag="$(printf '%s\n' "${managed_with_frag}" | jq --slurpfile f "${frag}" '. * $f[0]')"
done

merged_with_frag="$(printf '%s\n' "${sample_settings}" | jq --argjson managed "${managed_with_frag}" '. * $managed')"

printf '%s\n' "${merged_with_frag}" | jq -e '.testFragmentKey == true' >/dev/null || {
  echo "settings.d fragment key did not survive the merge" >&2
  exit 1
}

printf '%s\n' "${merged_with_frag}" | jq -e '.teammateMode == "solo"' >/dev/null || {
  echo "settings.d fragment did not override the base's teammateMode value" >&2
  exit 1
}

echo "claude settings.d fragment merges over the managed block and overrides base keys"

# Malformed-fragment case: a bad fragment must be skipped cleanly (not abort
# the pipeline, not clobber state built up from earlier-processed fragments).
# Exercises the same commit-on-success loop as ai-stack.nix's claudeSettingsMerge:
#   if tmp="$(... | jq ...)"; then managed="$tmp"; else warn; fi
baddir="$(mktemp -d)"
trap 'rm -rf "${fixture}" "${fragdir}" "${baddir}"' EXIT

cat >"${baddir}/01-good.json" <<'JSON'
{
  "goodFragmentKey": true
}
JSON
printf '%s\n' '{not json' >"${baddir}/02-bad.json"

managed_with_bad="$(cat "${base}")"
for frag in "${baddir}"/*.json; do
  [ -f "${frag}" ] || continue
  if tmp="$(printf '%s\n' "${managed_with_bad}" | jq --slurpfile f "${frag}" '. * $f[0]')"; then
    managed_with_bad="${tmp}"
  else
    echo "skipping bad fragment ${frag}" >&2
  fi
done

merged_with_bad="$(printf '%s\n' "${sample_settings}" | jq --argjson managed "${managed_with_bad}" '. * $managed')"

printf '%s\n' "${merged_with_bad}" | jq -e '.goodFragmentKey == true' >/dev/null || {
  echo "valid fragment before a malformed one was not applied" >&2
  exit 1
}

printf '%s\n' "${merged_with_bad}" | jq -e 'has("badFragmentKey") | not' >/dev/null || {
  echo "malformed fragment should not have contributed any key" >&2
  exit 1
}

echo "claude settings.d loop skips a malformed fragment and keeps prior fragment state"

# Extract the actual final transforms and publication, not a copy of the jq.
# Substitute only Nix's executable interpolation so hygiene CI needs no Nix.
normalization="$(awk '
  /# Seed cross-machine defaults/ { emit = 1 }
  emit && /^[[:space:]]*\) \|\| true/ { exit }
  emit { gsub(/\$\{jq\}/, "jq"); print }
' "${repo_root}/modules/home/ai-stack.nix")"
[ -n "$normalization" ] || { echo "could not extract settings normalization" >&2; exit 1; }

mkdir -p "$baddir/normalization-home"
printf '%s\n' "$sample_settings" > "$baddir/settings.before"
normalize_settings() (
  export HOME="$baddir/normalization-home"
  SETTINGS="$HOME/settings.json"
  merged="$1"
  eval "$normalization"
)

# First transform: malformed input. Second: syntactically valid but wrong type.
for invalid in '{not json' '{"sandbox":{"filesystem":"invalid"}}'; do
  cp "$baddir/settings.before" "$baddir/normalization-home/settings.json"
  # Match production's outer || true, which suppresses inherited errexit.
  normalize_settings "$invalid" > "$baddir/normalize.stdout" 2> "$baddir/normalize.stderr" || true
  if ! cmp -s "$baddir/settings.before" "$baddir/normalization-home/settings.json"; then
    echo "failed normalization replaced existing Claude settings" >&2
    exit 1
  fi
  if ! rg -Fq 'keeping existing settings' "$baddir/normalize.stderr"; then
    echo "failed normalization did not warn that settings were preserved" >&2
    exit 1
  fi
done

# The extracted block must still publish valid input and retain in-tool choices.
printf '{}\n' > "$baddir/normalization-home/settings.json"
normalize_settings "$sample_settings" || true
jq -e '
  .model == "haiku" and .effortLevel == "medium" and .theme == "dark"
  and (.sandbox.filesystem.allowWrite | index("/fixture/user-write") != null)
' "$baddir/normalization-home/settings.json" >/dev/null

echo "Claude settings normalization preserves the file on failure and publishes valid input"
