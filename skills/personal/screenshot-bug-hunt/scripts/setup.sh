#!/usr/bin/env bash
# Bootstrap Playwright + headless Chromium into a /tmp directory so we don't
# pollute the project's node_modules. Idempotent — safe to run repeatedly.
#
# After this completes, $WORKDIR/node_modules/.bin/playwright is on disk and
# Chromium is downloaded under ~/Library/Caches/ms-playwright (or platform
# equivalent). The shoot.mjs script imports from $WORKDIR/node_modules.

set -euo pipefail

WORKDIR="${HIPPO_PW_WORKDIR:-/tmp/screenshot-bug-hunt-pw}"

mkdir -p "$WORKDIR"

# Write a minimal package.json once. The pinned version matches what we tested
# against; bump only when a new feature requires it.
if [[ ! -f "$WORKDIR/package.json" ]]; then
  cat > "$WORKDIR/package.json" <<'EOF'
{
  "name": "screenshot-bug-hunt-pw",
  "private": true,
  "type": "module",
  "dependencies": {
    "playwright": "^1.55.0"
  }
}
EOF
fi

cd "$WORKDIR"

# Use whichever pkg manager is on PATH. pnpm is preferred (fast, disk-efficient
# global store), but plain npm works.
if command -v pnpm >/dev/null 2>&1; then
  pnpm install --silent
else
  npm install --silent
fi

# Download Chromium if not already cached. Playwright caches per-version under
# ~/Library/Caches/ms-playwright (macOS) or ~/.cache/ms-playwright (Linux).
"$WORKDIR/node_modules/.bin/playwright" install chromium >/dev/null 2>&1 || \
  "$WORKDIR/node_modules/.bin/playwright" install chromium

echo "OK: playwright ready at $WORKDIR"
echo "    use --workdir=$WORKDIR if you override the default location."
