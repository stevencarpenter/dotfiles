#!/usr/bin/env bash
# pre-commit commit-msg hook: strip Co-Authored-By: Claude trailers.
#
# dot_claude/CLAUDE.md prohibits Claude attribution in commits, but the
# Claude Code harness default still appends `Co-Authored-By: Claude ...`
# trailers. This hook removes them on the message file before the commit
# is finalized so the prohibition is enforced regardless of the source.

set -euo pipefail

msg_file="$1"

# Strip any line whose trailer subject is "Co-Authored-By: Claude" (case-insensitive).
sed -i.bak -E '/^Co-[Aa]uthored-[Bb]y: Claude/d' "$msg_file"
rm -f "${msg_file}.bak"
