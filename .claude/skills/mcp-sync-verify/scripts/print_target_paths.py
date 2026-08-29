#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["mcp-sync"]
#
# [tool.uv.sources]
# mcp-sync = { path = "../../../../mcp_sync" }
# ///
"""Print the HOME-relative paths mcp_sync will write, one per line.

Discovered from ``mcp_sync.sync._build_targets`` plus the special-cased
writers, so dry_run_diff.sh never goes stale when sync.py gains a target.
list_targets.py prints the same set in a human-readable form; this one is the
machine-readable feed.

Usage:
    uv run --project mcp_sync python \\
        .claude/skills/mcp-sync-verify/scripts/print_target_paths.py
"""

from __future__ import annotations

from pathlib import Path

from mcp_sync.sync import _build_targets


def main() -> int:
    """Print each destination path relative to the current user's home.

    Returns:
        Process exit status, always 0.
    """
    home = Path.home()
    seen = {str(t.destination.relative_to(home)) for t in _build_targets(home)}
    # Special-cased writers (see sync.py).
    seen.add(".codex/config.toml")
    seen.add(".claude.json")
    seen.add(".config/.copilot/config.json")
    for path in sorted(seen):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
