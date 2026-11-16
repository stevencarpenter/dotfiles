#!/usr/bin/env bash
# First installs that dfm has no resource for yet: the gh-axi skill, the Codex ponytail
# plugin and the private fantasy-sports agents. dfm sync runs it as the side-channels updater.
# dfm owns the rest: mise, DuckDB extensions, checkouts, the agent registry and lefthook.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
npx_bin="${NPX_BIN:-npx}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"

# Upstream owns this skill's content and cross-agent links. This adds the skill on a new
# machine; dfm sync's skills updater (npx skills@latest update) keeps it at its newest version.
if [ "$("$capability_bin" skills)" = "1" ]; then
  if ! command -v "$npx_bin" >/dev/null 2>&1; then
    echo "error: npx not found; cannot refresh the gh-axi skill" >&2
    exit 1
  fi
  echo "==> Refreshing upstream gh-axi skill"
  DISABLE_TELEMETRY=1 "$npx_bin" --yes skills@latest add \
    https://github.com/kunchenguid/gh-axi/tree/main/skills/gh-axi \
    --skill gh-axi --global --yes --agent claude-code codex pi junie
fi

identity="$("$capability_bin" --identity)"

# Private fantasy-sports agents + Cursor skill: personal identity only, because a work
# host cannot read the private repo and must not hold it. The clone needs GitHub SSH.
if [ "$identity" = "personal" ] && [ "$("$capability_bin" skills)" = "1" ]; then
  "$repo_root/scripts/install-fantasy-sports.sh"
else
  echo "==> Skipping fantasy-sports (identity: $identity, or skills capability disabled)"
fi

# Codex owns this plugin's configuration and cache; ensure it during sync.
# Installation failure is nonfatal. Hooks require node on PATH and approval
# through /hooks in a Codex session after installation.
if command -v codex >/dev/null 2>&1; then
  echo "==> Ensuring ponytail Codex plugin"
  codex plugin marketplace list 2>/dev/null | grep -q "ponytail" ||
    codex plugin marketplace add DietrichGebert/ponytail ||
    echo "warning: ponytail marketplace add failed" >&2
  plugin_list="$(codex plugin list 2>/dev/null)" || plugin_list=""
  if ! printf '%s\n' "$plugin_list" | awk '$1 == "ponytail@ponytail" && $2 == "installed," { found = 1 } END { exit !found }'; then
    codex plugin add ponytail@ponytail ||
      echo "warning: ponytail plugin add failed" >&2
  fi
else
  echo "warning: codex not found; ponytail Codex plugin not ensured" >&2
fi
