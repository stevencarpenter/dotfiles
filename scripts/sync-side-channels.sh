#!/usr/bin/env bash
# Network and SSH provisioning that runs after the dfm apply.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mise_bin="${MISE_BIN:-mise}"
npx_bin="${NPX_BIN:-npx}"
capability_bin="${HOST_CAPABILITY_BIN:-$repo_root/scripts/host-capability.sh}"

# dfm's mise updater installs and upgrades the configured tools.
if command -v "$mise_bin" >/dev/null 2>&1; then
  # yazi's duckdb previews only LOAD these (auto_install_extensions = false), and DuckDB
  # keeps extensions per version, so a DuckDB upgrade needs them installed again.
  echo "==> Installing DuckDB extensions for yazi previews"
  DUCKDB_AGENT_MODE=0 "$mise_bin" exec -- duckdb -init /dev/null -c "INSTALL spatial; INSTALL avro;" >/dev/null ||
    echo "warning: DuckDB extension install failed; xlsx and avro previews fall back to plain text" >&2
else
  echo "error: mise not found; cannot install the DuckDB extensions" >&2
  exit 1
fi

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

# Application-owned updates: setup provisions only; the running application owns
# code updates and coordinated restarts. See docs/adopting-a-config.md.
firstmate_enabled="$("$capability_bin" mcp)"
if [ "$firstmate_enabled" = "1" ]; then
  echo "==> Ensuring Firstmate installation (native updates)"
  "${FIRSTMATE_BIN:-$repo_root/home/.local/bin/firstmate}" --setup
fi

identity="$("$capability_bin" --identity)"

# Private fantasy-sports agents + Cursor skill: personal identity only, because a work
# host cannot read the private repo and must not hold it. The clone needs GitHub SSH.
if [ "$identity" = "personal" ] && [ "$("$capability_bin" skills)" = "1" ]; then
  "$repo_root/scripts/install-fantasy-sports.sh"
else
  echo "==> Skipping fantasy-sports (identity: $identity, or skills capability disabled)"
fi

# Install hooks during sync because this writes the checkout's .git directory.
if command -v lefthook >/dev/null 2>&1; then
  echo "==> Installing git hooks (lefthook)"
  # Hook installation failure must not abort the remaining sync.
  (cd "$repo_root" && lefthook install) ||
    echo "warning: lefthook install failed; git hooks not wired" >&2
else
  echo "warning: lefthook not found; git hooks not installed (run 'just sync-side-channels' after installing it)" >&2
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

# Request the application-owned workflow only after dependency installation
# succeeds. The native inbox owns delivery; a queued request is not completion.
if [ "$firstmate_enabled" = "1" ]; then
  echo "==> Requesting Firstmate's native update (asynchronous)"
  "${FIRSTMATE_BIN:-$repo_root/home/.local/bin/firstmate}" --request-update
fi
