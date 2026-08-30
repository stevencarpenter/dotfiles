#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Assert the use-railway DAL keeps psql SQL errors visible and nonzero.

The Railway skill pipes SQL through `railway ssh psql`. Without
``-v ON_ERROR_STOP=1`` a failing statement still exits 0, and a `2>/dev/null`
would hide the server's message, so a broken migration would read as success.
This stubs the ssh layer and checks both properties on the built command.

Usage:
    assert-railway-psql-errors.py <repo-root>
"""

from __future__ import annotations

import sys
from pathlib import Path

# dal.py is a vendored skill script, not an installable package. Insert its
# directory before the import so the name resolves at module scope.
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "skills/personal/use-railway/scripts"),
)

import dal  # noqa: E402


def main(argv: list[str]) -> int:
    """Run the psql error-visibility assertions against the repo's DAL module.

    Args:
        argv: Command-line arguments after the program name; one repo root.

    Returns:
        Process exit status: 0 when every assertion holds, 2 on bad usage.

    Raises:
        AssertionError: If the built psql command or its result regressed.
    """
    if len(argv) != 1:
        print("usage: assert-railway-psql-errors.py <repo-root>", file=sys.stderr)
        return 2

    repo_root = Path(argv[0])
    dal_dir = repo_root / "skills/personal/use-railway/scripts"
    if not dal_dir.is_dir():
        print(f"usage: no use-railway scripts under {repo_root}", file=sys.stderr)
        return 2

    captured: dict[str, object] = {}

    def failing_ssh(service, command, timeout):
        captured["service"] = service
        captured["command"] = command
        captured["timeout"] = timeout
        return 3, "", "ERROR: extension is unavailable\n"

    dal.run_ssh_query = failing_ssh
    code, output = dal.run_psql_query("postgres", "CREATE EXTENSION missing")

    assert "-v ON_ERROR_STOP=1" in captured["command"], captured["command"]
    assert "2>/dev/null" not in captured["command"], captured["command"]
    assert code == 3, code
    assert output == "ERROR: extension is unavailable\n", repr(output)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
