"""Command-line interface for aws_config_gen."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
from pathlib import Path
from typing import Sequence

from aws_config_gen.config_writer import render_profiles, write_config
from aws_config_gen.discovery import discover_all_roles
from aws_config_gen.naming import build_profile_entries, load_generator_config
from aws_config_gen.sso_token import TokenExpiredError, TokenNotFoundError


def _print_invalid_generator_config(path: Path, exc: Exception) -> None:
    print(
        f"Invalid generator config file {path}: {exc}",
        file=sys.stderr,
    )


def _print_write_config_error(path: Path, exc: Exception) -> None:
    print(
        f"Failed to write AWS config {path}: {exc}",
        file=sys.stderr,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aws-config-gen",
        description="Auto-generate AWS SSO profiles from Identity Center.",
    )
    parser.add_argument(
        "--generator-config",
        type=Path,
        default=None,
        help="Path to overrides.json (default: ~/.config/aws-config-gen/overrides.json).",
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
        else Path.home() / ".config" / "aws-config-gen" / "overrides.json"
    )
    try:
        generator_config = load_generator_config(generator_config_path)
    except FileNotFoundError:
        print(
            f"Generator config file not found: {generator_config_path}",
            file=sys.stderr,
        )
        return 1
    except (json.JSONDecodeError, KeyError, ValueError) as exc:
        _print_invalid_generator_config(generator_config_path, exc)
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
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            print(
                f"SSO token rejected (HTTP 401). Run `aws sso login --sso-session {generator_config.sso_session}` to re-authenticate.",
                file=sys.stderr,
            )
        else:
            print(
                f"AWS Identity Center API error (HTTP {exc.code}): {exc.reason}",
                file=sys.stderr,
            )
        return 1 if args.strict else 0
    except urllib.error.URLError as exc:
        print(
            f"Failed to reach AWS Identity Center: {exc.reason}",
            file=sys.stderr,
        )
        return 1 if args.strict else 0

    try:
        entries = build_profile_entries(roles, generator_config)
    except ValueError as exc:
        _print_invalid_generator_config(generator_config_path, exc)
        return 1

    generated_block = render_profiles(entries, generator_config)

    if args.dry_run:
        print(generated_block, end="")
        return 0

    try:
        write_config(config_path, generated_block)
    except ValueError as exc:
        _print_write_config_error(config_path, exc)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
