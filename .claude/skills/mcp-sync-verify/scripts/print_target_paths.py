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

import argparse
from pathlib import Path

from mcp_sync.sync import sync_destinations


def _print_pretty(kind_filter: str | None = None) -> int:
    """Print each destination grouped by wholesale vs in-place patch."""
    home = Path.home()
    dests = [
        d
        for d in sync_destinations(home)
        if kind_filter is None or d.kind == kind_filter
    ]
    print("# mcp_sync deployment targets")
    print()
    if kind_filter is None or kind_filter == "wholesale":
        print("## Generated wholesale:")
        for dest in dests:
            if dest.kind == "wholesale":
                print(f"  - {dest.name:<28} {dest.path}")
        print()
    if kind_filter is None or kind_filter == "patch":
        print("## Patched in place:")
        for dest in dests:
            if dest.kind == "patch":
                note = (
                    " (only mcpServers key is touched)" if dest.name == "claude" else ""
                )
                print(f"  - {dest.name:<28} {dest.path}{note}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """Print each destination path relative to the current user's home.

    Args:
        argv: Optional argument list; defaults to ``sys.argv[1:]``.
            ``--kind wholesale|patch`` restricts the listing;
            ``--pretty`` prints the grouped human-readable view instead.

    Returns:
        0 on success.

    Raises:
        SystemExit: With status 2 on usage errors, or 0 for help.
    """
    parser = argparse.ArgumentParser(
        description="Print mcp_sync deployment paths.", allow_abbrev=False
    )
    parser.add_argument("--kind", choices=("wholesale", "patch"))
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args(argv)

    if args.pretty:
        return _print_pretty(args.kind)

    home = Path.home()
    for dest in sync_destinations(home):
        if args.kind is not None and dest.kind != args.kind:
            continue
        print(dest.path.relative_to(home))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
