"""Module entrypoint for python -m mcp_sync."""

from __future__ import annotations

from .cli import cli


if __name__ == "__main__":
    raise SystemExit(cli())
