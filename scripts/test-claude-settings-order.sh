#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${repo_root}/dot_claude/modify_settings.json.tmpl"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-order.XXXXXX")"
trap 'rm -rf "${workdir}"' EXIT

rendered_script="${workdir}/modify-settings.sh"
chezmoi --source="${repo_root}" execute-template < "${template}" > "${rendered_script}"
chmod +x "${rendered_script}"

sample_settings=$(cat <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "cleanupPeriodDays": 30,
  "env": {
    "ENABLE_LSP_TOOL": "0"
  },
  "permissions": {
    "allow": [
      "WebFetch(domain:example.com)"
    ],
    "defaultMode": "acceptEdits"
  },
  "model": "haiku",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "old"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "old"
  },
  "enabledPlugins": {
    "understand-anything@understand-anything": true
  },
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": {
        "source": "github",
        "repo": "old/repo"
      }
    }
  },
  "sandbox": {
    "filesystem": {
      "allowWrite": [
        "/tmp/custom"
      ]
    }
  },
  "effortLevel": "medium",
  "autoDreamEnabled": false,
  "skipDangerousModePermissionPrompt": false,
  "theme": "dark",
  "editorMode": "vim",
  "preferredNotifChannel": "ghostty",
  "teammateMode": "tmux",
  "remoteControlAtStartup": true,
  "inputNeededNotifEnabled": false,
  "skipAutoPermissionPrompt": false,
  "voiceEnabled": true
}
JSON
)

output="$(printf '%s\n' "${sample_settings}" | "${rendered_script}")"

assert_order_preserved() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    {
      echo "${label} key order changed"
      diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") || true
    } >&2
    exit 1
  fi
}

# The sample is intentionally non-alphabetical, like a Claude-written settings
# file. The expected order comes from the input fixture, not a pinned release's
# complete key list, so new Claude Code settings do not require updating this
# test unless the preservation behavior itself changes.
expected_top_level_order="$(printf '%s\n' "${sample_settings}" | jq -r 'keys_unsorted[]')"
actual_top_level_order="$(printf '%s\n' "${output}" | jq -r 'keys_unsorted[]')"
assert_order_preserved "top-level settings" "${expected_top_level_order}" "${actual_top_level_order}"

expected_command_order="$(
  printf '%s\n' "${sample_settings}" | jq -r '.hooks.PostToolUse[0].hooks[0] | keys_unsorted[]'
)"
actual_command_order="$(
  printf '%s\n' "${output}" | jq -r '.hooks.PostToolUse[0].hooks[0] | keys_unsorted[]'
)"
assert_order_preserved "hook command" "${expected_command_order}" "${actual_command_order}"

expected_marketplace_source_order="$(
  printf '%s\n' "${sample_settings}" | jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | keys_unsorted[]'
)"
actual_marketplace_source_order="$(
  printf '%s\n' "${output}" | jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | keys_unsorted[]'
)"
assert_order_preserved \
  "marketplace source" \
  "${expected_marketplace_source_order}" \
  "${actual_marketplace_source_order}"

echo "claude settings order is preserved"
