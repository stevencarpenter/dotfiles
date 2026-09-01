#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Validate the structure of home/.config/mcp/mcp-master.json.

mcp_sync merges this file into every tool-specific config, so a shape error
here fans out to Claude, Codex, Cursor, Copilot, and the rest. Master may
define zero shared servers; the per-machine servers live in the overlays under
home/.config/mcp/machine/.

Usage:
    validate-mcp-master.py [path]   (default: home/.config/mcp/mcp-master.json)
"""

import json
import sys
from pathlib import Path

DEFAULT_PATH = Path("home/.config/mcp/mcp-master.json")


def validate(path: Path) -> "list[str]":
    """Collect structural errors in the master MCP config.

    Args:
        path: Path to mcp-master.json.

    Returns:
        Error messages, empty when the file is well-formed.
    """
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return [f"{path} must be a JSON object"]

    servers = data.get("servers")
    if not isinstance(servers, dict):
        return [f"{path} must define a 'servers' object"]

    errors = []
    for server_name, server_config in servers.items():
        if not isinstance(server_config, dict):
            errors.append(f"Server '{server_name}' must be a JSON object")
            continue
        if server_config.get("type") == "stdio" and not server_config.get("command"):
            errors.append(f"Server '{server_name}' uses stdio but has no 'command'")
    return errors


def main(argv: "list[str]") -> int:
    """Validate the master MCP config named on the command line.

    Args:
        argv: Command-line arguments after the program name; an optional path.

    Returns:
        Process exit status: 0 when valid, 1 on structural errors, 2 on usage.
    """
    if len(argv) > 1:
        print("usage: validate-mcp-master.py [path]", file=sys.stderr)
        return 2
    path = Path(argv[0]) if argv else DEFAULT_PATH
    errors = validate(path)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"{path}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
