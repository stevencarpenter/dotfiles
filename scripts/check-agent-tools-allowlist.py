#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
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


def tools_declarations(frontmatter: str) -> "list[tuple[int, str, list[str]]]":
    """Find every ``tools:`` declaration in an agent's frontmatter block.

    YAML admits two forms for the same value and agent files use both: the
    inline flow ``tools: Read, Bash`` and a block sequence whose entries sit on
    the following indented ``- Item`` lines. Reading only the text after the
    colon yields an empty list for the block form, which then satisfies every
    downstream check silently.

    Args:
        frontmatter: Text between the opening and closing ``---`` fences.

    Returns:
        One ``(line_number, rendered_line, tools)`` triple per declaration,
        where ``line_number`` is 1-based within the whole file and
        ``rendered_line`` is suitable for a violation message.
    """
    lines = frontmatter.splitlines()
    declarations = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("tools:"):
            index += 1
            continue
        line_number = index + 2  # +1 for 1-based, +1 for the opening fence
        inline = line.split(":", 1)[1].strip()
        index += 1
        if inline:
            tools = [part.strip() for part in inline.split(",")]
            declarations.append((line_number, line, [tool for tool in tools if tool]))
            continue
        tools = []
        while index < len(lines):
            item = lines[index]
            if not item.startswith((" ", "\t")):
                break
            entry = item.strip()
            if not entry.startswith("- "):
                break
            tools.append(entry[2:].strip())
            index += 1
        tools = [tool for tool in tools if tool]
        declarations.append((line_number, "tools: " + ", ".join(tools), tools))
    return declarations


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
        for line_number, rendered, tools in tools_declarations(frontmatter):
            if tools and all(tool in BUILTIN_TOOLS for tool in tools):
                found.append(f"{path.name}:{line_number}: {rendered}")
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
