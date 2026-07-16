"""Command-line interface for MCP sync."""

from __future__ import annotations

import argparse
from pathlib import Path
from collections.abc import Sequence

from .capture import run_capture
from .drift import run_check
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
    parser.add_argument(
        "--machine-config",
        type=Path,
        default=None,
        help="Path to machine-specific overlay JSON (deep-merged into master before per-tool transforms).",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="Report drift between deployed configs and what a sync would write; never writes. Exit 1 on drift.",
    )
    mode.add_argument(
        "--capture",
        metavar="TARGET",
        default=None,
        help="Capture a target's deployed drift into ~/.config/mcp/overrides/<key>.json so it survives future syncs.",
    )
    return parser


def cli(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    home = args.home.expanduser() if args.home else None
    master = args.master.expanduser() if args.master else None
    machine_config = args.machine_config.expanduser() if args.machine_config else None

    if args.check:
        return run_check(
            master_path=master, home=home, machine_config_path=machine_config
        )

    if args.capture is not None:
        return run_capture(
            args.capture,
            master_path=master,
            home=home,
            machine_config_path=machine_config,
        )

    return run_sync(master_path=master, home=home, machine_config_path=machine_config)


if __name__ == "__main__":
    raise SystemExit(cli())
