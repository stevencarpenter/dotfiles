#!/usr/bin/env bash
# Sync steps that dfm has no resource for yet: hooks-sync (MCP client configs, then the skills
# fan-out), the gh-axi skill and the Codex ponytail plugin. dfm sync runs this script through
# `just sync-side-channels` as its side-channels updater: detached, with no terminal and a
# cleared environment. dfm shows none of the output, so all of it also goes to the log below.
# Every step runs even when an earlier one failed. The script exits 1 when a step failed.
# dfm owns the rest: mise, DuckDB extensions, checkouts, the agent registry and lefthook.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
npx_bin="${NPX_BIN:-npx}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"
hooks_sync_bin="${HOOKS_SYNC_BIN:-$repo_root/scripts/hooks-sync.sh}"
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
log="$log_dir/side-channels.log"

hooks_sync() {
  echo "==> hooks-sync: MCP client configs, then the skills fan-out"
  "$hooks_sync_bin"
}

# Upstream owns this skill's content and cross-agent links. This adds the skill on a new
# machine; dfm sync's skills updater (npx skills@latest update) keeps it at its newest version.
gh_axi_skill() {
  [ "$("$capability_bin" skills)" = "1" ] || return 0
  if ! command -v "$npx_bin" >/dev/null 2>&1; then
    echo "error: npx not found; cannot refresh the gh-axi skill" >&2
    return 1
  fi
  echo "==> Refreshing upstream gh-axi skill"
  DISABLE_TELEMETRY=1 "$npx_bin" --yes skills@latest add \
    https://github.com/kunchenguid/gh-axi/tree/main/skills/gh-axi \
    --skill gh-axi --global --yes --agent claude-code codex pi junie
}

# Codex owns this plugin's configuration and cache; ensure it during sync.
# Installation failure is nonfatal. Hooks require node on PATH and approval
# through /hooks in a Codex session after installation.
ponytail_plugin() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "warning: codex not found; ponytail Codex plugin not ensured" >&2
    return 0
  fi
  echo "==> Ensuring ponytail Codex plugin"
  codex plugin marketplace list 2>/dev/null | grep -q "ponytail" ||
    codex plugin marketplace add DietrichGebert/ponytail ||
    echo "warning: ponytail marketplace add failed" >&2
  plugin_list="$(codex plugin list 2>/dev/null)" || plugin_list=""
  if ! printf '%s\n' "$plugin_list" | awk '$1 == "ponytail@ponytail" && $2 == "installed," { found = 1 } END { exit !found }'; then
    codex plugin add ponytail@ponytail ||
      echo "warning: ponytail plugin add failed" >&2
  fi
  return 0
}

main() {
  failed=""
  hooks_sync || failed="$failed hooks-sync"
  gh_axi_skill || failed="$failed gh-axi"
  ponytail_plugin
  if [ -n "$failed" ]; then
    echo "side-channels: failed steps:$failed; full output in $log" >&2
    return 1
  fi
  echo "side-channels: all steps passed; full output in $log"
}

mkdir -p "$log_dir" && (umask 077 && : >"$log") && chmod 600 "$log" ||
  { echo "error: cannot write the log $log" >&2; exit 1; }
main 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
