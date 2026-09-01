#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Fail when a generated Claude agent declares a built-in-only tools allowlist.

An agent whose ``tools:`` frontmatter names nothing but Claude's built-in tools
silently loses the MCP servers and skills it was configured with. That is a
failed sync, not a degraded-but-usable install, so scripts/install-agent-registry.sh
treats it as fatal.

Usage:
    check-agent-tools-allowlist.py <agents-dir>
"""

import sys
from pathlib import Path

BUILTIN_TOOLS = {
    "Read",
    "Write",
    "Edit",
    "MultiEdit",
    "NotebookEdit",
    "Bash",
    "Glob",
    "Grep",
    "LS",
}


def violations(root: Path) -> "list[str]":
    """Collect one message per agent file whose tools list is built-in-only.

    Args:
        root: Directory holding the generated ``*.md`` Claude agent files.

    Returns:
        Human-readable violation lines, empty when every agent is acceptable.
    """
    found = []
    for path in sorted(root.glob("*.md")) if root.is_dir() else []:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            found.append(f"{path.name}: cannot read: {exc}")
            continue
        if not text.startswith("---\n"):
            continue
        frontmatter = text[4:].split("\n---\n", 1)[0]
        for line_number, line in enumerate(frontmatter.splitlines(), start=2):
            if not line.startswith("tools:"):
                continue
            tools = [part.strip() for part in line.split(":", 1)[1].split(",")]
            tools = [tool for tool in tools if tool]
            if tools and all(tool in BUILTIN_TOOLS for tool in tools):
                found.append(f"{path.name}:{line_number}: {line}")
    return found


def main(argv: "list[str]") -> int:
    """Report built-in-only tools allowlists under the given agents directory.

    Args:
        argv: Command-line arguments after the program name; one agents path.

    Returns:
        Process exit status: 0 when clean, 1 on violations, 2 on bad usage.
    """
    if len(argv) != 1:
        print("usage: check-agent-tools-allowlist.py <agents-dir>", file=sys.stderr)
        return 2
    found = violations(Path(argv[0]))
    if not found:
        return 0
    print("error: Claude agents contain built-in-only tools allowlists:", file=sys.stderr)
    print("\n".join(found), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
