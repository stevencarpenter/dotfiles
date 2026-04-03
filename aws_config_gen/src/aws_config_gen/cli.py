"""Command-line interface for aws_config_gen."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from aws_config_gen.config_writer import render_profiles, write_config
from aws_config_gen.discovery import discover_all_roles
from aws_config_gen.naming import build_profile_entries, load_generator_config
from aws_config_gen.sso_token import TokenExpiredError, TokenNotFoundError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aws-config-gen",
        description="Auto-generate AWS SSO profiles from Identity Center.",
    )
    parser.add_argument(
        "--generator-config",
        type=Path,
        default=None,
        help="Path to config.json (default: ~/.config/aws-config-gen/config.json).",
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

    generator_config_path: Path = (
        args.generator_config.expanduser()
        if args.generator_config
        else Path.home() / ".config" / "aws-config-gen" / "config.json"
    )
    try:
        generator_config = load_generator_config(generator_config_path)
    except FileNotFoundError:
        print(
            f"Generator config file not found: {generator_config_path}",
            file=sys.stderr,
        )
        return 1
    except (json.JSONDecodeError, KeyError) as exc:
        print(
            f"Invalid generator config file {generator_config_path}: {exc}",
            file=sys.stderr,
        )
        return 1

    config_path: Path = (
        args.config.expanduser() if args.config else Path.home() / ".aws" / "config"
    )

    try:
        roles = discover_all_roles(
            generator_config.sso_session,
            generator_config.sso_region,
            generator_config.skip,
        )
    except TokenExpiredError:
        print(
            f"Run `aws sso login --sso-session {generator_config.sso_session}` to refresh.",
            file=sys.stderr,
        )
        return 1 if args.strict else 0
    except TokenNotFoundError:
        print(
            f"Run `aws sso login --sso-session {generator_config.sso_session}` to authenticate.",
            file=sys.stderr,
        )
        return 1 if args.strict else 0

    entries = build_profile_entries(roles, generator_config)
    generated_block = render_profiles(entries, generator_config)

    if args.dry_run:
        print(generated_block, end="")
        return 0

    write_config(config_path, generated_block)
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
