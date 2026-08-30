#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["mcp-sync"]
#
# [tool.uv.sources]
# mcp-sync = { path = "../../../../mcp_sync", editable = true }
# ///
"""Print the set of paths mcp_sync will (over)write, discovered dynamically.

Reads :func:`mcp_sync.sync.sync_destinations` so this never goes stale when a
target is added in ``sync.py``. ``print_target_paths.py`` prints the same set
as a machine-readable feed.

Usage:
    .claude/skills/mcp-sync-verify/scripts/list_targets.py
"""

from __future__ import annotations

from pathlib import Path

from mcp_sync.sync import sync_destinations


def main() -> int:
    """Print each destination grouped by wholesale vs in-place patch.

    Returns:
        Process exit status, always 0.
    """
    home = Path.home()
    dests = sync_destinations(home)
    print("# mcp_sync deployment targets")
    print()
    print("## Generated wholesale:")
    for dest in dests:
        if dest.kind == "wholesale":
            print(f"  - {dest.name:<28} {dest.path}")
    print()
    print("## Patched in place:")
    for dest in dests:
        if dest.kind != "patch":
            continue
        note = ""
        if dest.name == "claude":
            note = " (only mcpServers key is touched)"
        print(f"  - {dest.name:<28} {dest.path}{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
