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

The check covers the agents the registry itself installed, named by the manifest
the installer writes beside them. ``~/.claude/agents`` is a shared directory:
Claude Code plugins drop their own agents there, and a plugin agent that is
deliberately built-in only (the impeccable-* set, for one) is not a failed sync
of this repo's registry. Globbing the directory turned every such third-party
file into a hard `just sync` failure.

Usage:
    check-agent-tools-allowlist.py <agents-dir> [manifest]

``manifest`` defaults to ``<agents-dir>/.installed-by-agent-registry.json`` and
must exist: the installer writes it, so a missing manifest means the install did
not complete and the allowlist guarantee cannot be checked.
"""

import json
import sys
from pathlib import Path

MANIFEST_NAME = ".installed-by-agent-registry.json"

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


def manifest_names(manifest: Path) -> "list[str]":
    """Read the installer's manifest as a list of agent file names.

    Args:
        manifest: Path to the JSON manifest written by the registry install.

    Returns:
        The file names the registry installed, in manifest order.

    Raises:
        ValueError: The manifest is absent, unreadable, or not a list of names.
    """
    try:
        raw = manifest.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"cannot read agent manifest {manifest}: {exc}") from exc
    try:
        entries = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"malformed agent manifest {manifest}: {exc}") from exc
    if not isinstance(entries, list) or not all(isinstance(e, str) for e in entries):
        raise ValueError(f"agent manifest {manifest} is not a list of file names")
    return entries


def violations(root: Path, names: "list[str]") -> "list[str]":
    """Collect one message per manifest agent whose tools list is built-in-only.

    Args:
        root: Directory holding the generated ``*.md`` Claude agent files.
        names: Agent file names the registry installed; files outside this set
            belong to plugins or earlier registries and are not checked.

    Returns:
        Human-readable violation lines, empty when every agent is acceptable.
    """
    found = []
    for name in sorted(names):
        path = root / name
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            found.append(f"{name}: cannot read: {exc}")
            continue
        if not text.startswith("---\n"):
            continue
        frontmatter = text[4:].split("\n---\n", 1)[0]
        for line_number, rendered, tools in tools_declarations(frontmatter):
            if tools and all(tool in BUILTIN_TOOLS for tool in tools):
                found.append(f"{name}:{line_number}: {rendered}")
    return found


def main(argv: "list[str]") -> int:
    """Report built-in-only tools allowlists among the installed agents.

    Args:
        argv: Command-line arguments after the program name: the agents
            directory, and optionally an explicit manifest path.

    Returns:
        Process exit status: 0 when clean, 1 on violations or an unusable
        manifest, 2 on bad usage.
    """
    if not 1 <= len(argv) <= 2:
        print(
            "usage: check-agent-tools-allowlist.py <agents-dir> [manifest]",
            file=sys.stderr,
        )
        return 2
    root = Path(argv[0])
    manifest = Path(argv[1]) if len(argv) == 2 else root / MANIFEST_NAME
    try:
        names = manifest_names(manifest)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    found = violations(root, names)
    if not found:
        return 0
    print("error: Claude agents contain built-in-only tools allowlists:", file=sys.stderr)
    print("\n".join(found), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
