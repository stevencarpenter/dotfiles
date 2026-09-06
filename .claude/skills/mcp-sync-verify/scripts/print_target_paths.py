#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["mcp-sync"]
#
# [tool.uv.sources]
# mcp-sync = { path = "../../../../mcp_sync", editable = true }
# ///
"""Print the paths mcp_sync will write, discovered dynamically.

Reads :func:`mcp_sync.sync.sync_destinations`, so this never goes stale when
a wholesale target, the Codex TOML patch, or a JSON patch spec is added.

Usage:
    .claude/skills/mcp-sync-verify/scripts/print_target_paths.py
    .claude/skills/mcp-sync-verify/scripts/print_target_paths.py --kind patch
    .claude/skills/mcp-sync-verify/scripts/print_target_paths.py --pretty
"""

from __future__ import annotations

import sys
from pathlib import Path

from mcp_sync.sync import sync_destinations

_KINDS = frozenset({"wholesale", "patch"})
_USAGE = "usage: print_target_paths.py [--kind wholesale|patch] [--pretty]"


def _print_pretty() -> int:
    """Print each destination grouped by wholesale vs in-place patch."""
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


def main(argv: list[str] | None = None) -> int:
    """Print each destination path relative to the current user's home.

    Args:
        argv: Optional argument list; defaults to ``sys.argv[1:]``.
            ``--kind wholesale|patch`` restricts the listing;
            ``--pretty`` prints the grouped human-readable view instead.

    Returns:
        0 on success, 2 on usage errors.
    """
    args = list(sys.argv[1:] if argv is None else argv)
    kind_filter: str | None = None
    pretty = False
    while args:
        arg = args.pop(0)
        if arg == "--pretty":
            pretty = True
        elif arg == "--kind":
            if not args or args[0] not in _KINDS:
                print(_USAGE, file=sys.stderr)
                return 2
            kind_filter = args.pop(0)
        else:
            print(_USAGE, file=sys.stderr)
            return 2

    if pretty:
        return _print_pretty()

    home = Path.home()
    for dest in sync_destinations(home):
        if kind_filter is not None and dest.kind != kind_filter:
            continue
        print(dest.path.relative_to(home))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
