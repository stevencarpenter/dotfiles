#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["mcp-sync"]
#
# [tool.uv.sources]
# mcp-sync = { path = "../../../../mcp_sync", editable = true }
# ///
"""Print the HOME-relative paths mcp_sync will write, one per line.

Reads :func:`mcp_sync.sync.sync_destinations`, so this never goes stale when
a wholesale target, the Codex TOML patch, or a JSON patch spec is added.

Usage:
    .claude/skills/mcp-sync-verify/scripts/print_target_paths.py
    .claude/skills/mcp-sync-verify/scripts/print_target_paths.py --kind patch
"""

from __future__ import annotations

import sys
from pathlib import Path

from mcp_sync.sync import sync_destinations

_KINDS = frozenset({"wholesale", "patch"})


def main(argv: list[str] | None = None) -> int:
    """Print each destination path relative to the current user's home.

    Args:
        argv: Optional argument list; defaults to ``sys.argv[1:]``.
            ``--kind wholesale|patch`` restricts the listing.

    Returns:
        0 on success, 2 on usage errors.
    """
    args = list(sys.argv[1:] if argv is None else argv)
    kind_filter: str | None = None
    if args[:1] == ["--kind"]:
        if len(args) != 2 or args[1] not in _KINDS:
            print(
                "usage: print_target_paths.py [--kind wholesale|patch]",
                file=sys.stderr,
            )
            return 2
        kind_filter = args[1]
    elif args:
        print(
            "usage: print_target_paths.py [--kind wholesale|patch]",
            file=sys.stderr,
        )
        return 2

    home = Path.home()
    for dest in sync_destinations(home):
        if kind_filter is not None and dest.kind != kind_filter:
            continue
        print(dest.path.relative_to(home))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
