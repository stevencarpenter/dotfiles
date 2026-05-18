#!/usr/bin/env bash
# Run mcp_sync against a sandbox HOME, then diff every generated file against
# the currently-deployed copy under $REAL_HOME. No writes to real config.
#
# Why a sandbox HOME instead of --dry-run? mcp_sync has no --dry-run flag (see
# mcp_sync/src/mcp_sync/cli.py). Pointing --home at a tmpdir, then seeding the
# master config + per-tool overrides into it, gives us the full real output we
# can diff non-destructively.
#
# Usage:
#   bash .claude/skills/mcp-sync-verify/scripts/dry_run_diff.sh [machine_overlay.json]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
REAL_HOME="${HOME}"
SANDBOX="$(mktemp -d -t mcp-sync-verify.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# Optional machine overlay arg. If omitted, auto-detect like the chezmoi hook does.
MACHINE_ARG=()
if [[ $# -ge 1 ]]; then
  MACHINE_ARG=(--machine-config "$1")
else
  shopt -s nullglob
  for f in "$REAL_HOME"/.config/mcp/machine/*.json; do
    MACHINE_ARG=(--machine-config "$f")
    break
  done
  shopt -u nullglob
fi

# Seed the sandbox with the master + per-tool override sources from the repo.
mkdir -p "$SANDBOX/.config/mcp/overrides"
cp "$REPO_ROOT/dot_config/mcp/mcp-master.json" "$SANDBOX/.config/mcp/mcp-master.json"
if [[ -d "$REPO_ROOT/dot_config/mcp/overrides" ]]; then
  cp -R "$REPO_ROOT/dot_config/mcp/overrides/." "$SANDBOX/.config/mcp/overrides/"
fi

# Mirror the deployed Claude/Copilot files so the in-place patchers have
# something to patch (otherwise they log "skipping: file not found").
if [[ -f "$REAL_HOME/.claude.json" ]]; then
  cp "$REAL_HOME/.claude.json" "$SANDBOX/.claude.json"
fi
if [[ -f "$REAL_HOME/.config/.copilot/config.json" ]]; then
  mkdir -p "$SANDBOX/.config/.copilot"
  cp "$REAL_HOME/.config/.copilot/config.json" "$SANDBOX/.config/.copilot/config.json"
fi

echo "==> Running mcp_sync against sandbox HOME=$SANDBOX"
( cd "$REPO_ROOT" && uv run --project mcp_sync sync-mcp-configs --home "$SANDBOX" "${MACHINE_ARG[@]}" )

echo
echo "==> Diffing sandbox output vs deployed files under $REAL_HOME"
echo "    (no diff output = file is already in sync)"
echo

# Discover targets dynamically from sync.py rather than hard-coding paths.
mapfile -t REL_PATHS < <(
  cd "$REPO_ROOT" && uv run --project mcp_sync python - <<'PY'
from pathlib import Path
from mcp_sync.sync import _build_targets

home = Path.home()
seen = set()
for t in _build_targets(home):
    rel = t.destination.relative_to(home)
    seen.add(str(rel))
    if t.legacy_destination:
        seen.add(str(t.legacy_destination.relative_to(home)))
# Special-cased writers
seen.add(".codex/config.toml")
seen.add(".claude.json")
seen.add(".config/.copilot/config.json")
for p in sorted(seen):
    print(p)
PY
)

DIFFS=0
for rel in "${REL_PATHS[@]}"; do
  sandbox_file="$SANDBOX/$rel"
  deployed_file="$REAL_HOME/$rel"
  if [[ ! -f "$sandbox_file" && ! -f "$deployed_file" ]]; then
    continue
  fi
  if [[ ! -f "$sandbox_file" ]]; then
    echo "--- ($rel) only deployed, not regenerated"
    continue
  fi
  if [[ ! -f "$deployed_file" ]]; then
    echo "+++ ($rel) only in sandbox, not yet deployed"
    DIFFS=$((DIFFS + 1))
    continue
  fi
  if ! diff -q "$deployed_file" "$sandbox_file" > /dev/null; then
    echo "### diff: $rel"
    diff -u "$deployed_file" "$sandbox_file" || true
    echo
    DIFFS=$((DIFFS + 1))
  fi
done

echo
if [[ $DIFFS -eq 0 ]]; then
  echo "==> All deployed configs match what mcp_sync would generate. Nothing to apply."
else
  echo "==> $DIFFS file(s) would change. Run 'chezmoi apply' to deploy (or sync-mcp-configs)."
fi
