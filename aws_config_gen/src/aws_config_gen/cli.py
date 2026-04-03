"""Command-line interface for aws_config_gen."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

from aws_config_gen.config_writer import render_profiles, write_config
from aws_config_gen.discovery import discover_all_roles
from aws_config_gen.naming import build_profile_entries, load_overrides
from aws_config_gen.sso_token import TokenExpiredError, TokenNotFoundError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aws-config-gen",
        description="Auto-generate AWS SSO profiles from Identity Center.",
    )
    parser.add_argument(
        "--session",
        default="lumin",
        help="SSO session name (default: lumin).",
    )
    parser.add_argument(
        "--overrides",
        type=Path,
        default=None,
        help="Path to overrides.json (default: auto-detect from package dir).",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="Path to AWS config file (default: ~/.aws/config).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print generated config to stdout instead of writing.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 on token failures (default: exit 0).",
    )
    return parser


def cli(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    overrides_path: Path = (
        args.overrides.expanduser()
        if args.overrides
        else Path(__file__).resolve().parents[2] / "overrides.json"
    )
    overrides = load_overrides(overrides_path)

    config_path: Path = (
        args.config.expanduser() if args.config else Path.home() / ".aws" / "config"
    )

    try:
        roles = discover_all_roles(args.session, overrides.sso_region, overrides.skip)
    except TokenExpiredError:
        print(
            f"Run `aws sso login --sso-session {args.session}` to refresh.",
            file=sys.stderr,
        )
        return 1 if args.strict else 0
    except TokenNotFoundError:
        print(
            f"Run `aws sso login --sso-session {args.session}` to authenticate.",
            file=sys.stderr,
        )
        return 1 if args.strict else 0

    entries = build_profile_entries(roles, overrides)
    generated_block = render_profiles(entries, overrides)

    if args.dry_run:
        print(generated_block, end="")
        return 0

    write_config(config_path, generated_block)
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
