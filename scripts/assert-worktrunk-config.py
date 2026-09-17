#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Validate Worktrunk configuration types without freezing user preferences.

Parsed independently of the installed Worktrunk version. These assertions catch
a Nix store path accidentally committed as file contents.

Usage:
    assert-worktrunk-config.py <config.toml>
"""

import sys
from pathlib import Path

import tomllib


def main(argv: list[str]) -> int:
    """Check the Worktrunk config at the given path.

    Args:
        argv: Command-line arguments after the program name; one config path.

    Returns:
        Process exit status: 0 when every assertion holds, 2 on bad usage.

    Raises:
        AssertionError: If a required setting is missing or has drifted.
    """
    if len(argv) != 1:
        print("usage: assert-worktrunk-config.py <config.toml>", file=sys.stderr)
        return 2

    config = tomllib.loads(Path(argv[0]).read_text())
    if "worktree-path" in config:
        assert isinstance(config["worktree-path"], str) and config["worktree-path"]
    for section in ("list", "commit", "merge"):
        assert isinstance(config.get(section, {}), dict), f"{section} must be a table"
    for key in ("squash", "commit"):
        if key in config.get("merge", {}):
            assert type(config["merge"][key]) is bool, f"merge.{key} must be boolean"
    generation = config.get("commit", {}).get("generation", {})
    assert isinstance(generation, dict), "commit.generation must be a table"
    if "command" in generation:
        assert isinstance(generation["command"], str) and generation["command"]
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
