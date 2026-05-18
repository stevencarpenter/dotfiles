"""Command-line interface for skill synchronization."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .skills import run_skills_sync


def build_parser() -> argparse.ArgumentParser:
    """Build the ``sync-skills`` argument parser."""
    parser = argparse.ArgumentParser(
        prog="sync-skills",
        description="Sync Claude Code skills to ~/.claude/skills/.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Path to skills-master.json "
        "(defaults to ~/.config/skills/skills-master.json).",
    )
    parser.add_argument(
        "--machine-config",
        type=Path,
        default=None,
        help="Path to the machine overlay JSON, deep-merged into the manifest.",
    )
    parser.add_argument(
        "--home",
        type=Path,
        default=None,
        help="Override home directory (useful for testing).",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Override the chezmoi repo root (defaults to ~/.local/share/chezmoi).",
    )
    return parser


def cli(argv: Sequence[str] | None = None) -> int:
    """Entry point for the ``sync-skills`` console script."""
    args = build_parser().parse_args(argv)
    return run_skills_sync(
        manifest_path=args.manifest.expanduser() if args.manifest else None,
        machine_config_path=(
            args.machine_config.expanduser() if args.machine_config else None
        ),
        home=args.home.expanduser() if args.home else None,
        repo_root=args.repo_root.expanduser() if args.repo_root else None,
    )


if __name__ == "__main__":
    raise SystemExit(cli())
