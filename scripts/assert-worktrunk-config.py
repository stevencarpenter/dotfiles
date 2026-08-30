#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Assert the checked-in Worktrunk config keeps its behavior-defining settings.

Parsed independently of the installed Worktrunk version. These assertions catch
a Nix store path accidentally committed as file contents, and preserve the
settings whose absence changes worktree and merge behavior.

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
    assert config["worktree-path"] == "{{ repo_path }}/../{{ repo }}-{{ branch | sanitize }}"
    assert config["pre-start"] == [{"copy": "wt step copy-ignored"}]
    assert config["list"]["json-schema"] == 2
    assert config["commit"]["stage"] == "all"
    assert config["commit"]["generation"]["command"]
    assert config["merge"] == {"squash": True, "commit": True}
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
