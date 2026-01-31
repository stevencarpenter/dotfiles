"""Command-line interface for MCP sync."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .sync import run_sync


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sync-mcp-configs",
        description="Sync MCP server configurations across supported tools.",
    )
    parser.add_argument(
        "--master",
        type=Path,
        default=None,
        help="Path to mcp-master.json (defaults to ~/.config/mcp/mcp-master.json).",
    )
    parser.add_argument(
        "--home",
        type=Path,
        default=None,
        help="Override home directory (useful for testing).",
    )
    return parser


def cli(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    home = args.home.expanduser() if args.home else None
    master = args.master.expanduser() if args.master else None

    return run_sync(master_path=master, home=home)


if __name__ == "__main__":
    raise SystemExit(cli())
