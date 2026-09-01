#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Filter a list of paths down to the Python files, NUL-separated on stdout.

lefthook has no equivalent of pre-commit's `types: [python]` filter, which
matched on content as well as name. A `glob: "*.py"` job therefore skips
extensionless Python entirely: `home/.local/bin/op-adopt` and
`home/.local/bin/worktrunk-commit-generator` are both real Python that a
`.py` glob never sees, so `check-ast` stopped covering them in the
pre-commit -> lefthook port. Python-only jobs pipe their file list through
this first to get the content match back.

A file counts as Python when its name ends in `.py` or its first line is a
shebang naming a python interpreter, including the PEP 723 `uv run --script`
form this repo uses. Output is NUL-separated for `xargs -0`, so paths
containing spaces survive.

Usage:
    hook-python-files.py [path...] | xargs -0 <python-only-command>
"""

import re
import sys
from pathlib import Path

PEEK_BYTES = 200
SHEBANG_RE = re.compile(rb"^#!.*(?:python|uv run)")


def is_python(path: Path) -> bool:
    """Report whether a path is a Python source file.

    Args:
        path: Candidate file.

    Returns:
        True when the path is a regular file whose name ends in `.py` or
        whose first line is a python-naming shebang; False for directories,
        unreadable paths, and everything else.
    """
    try:
        if not path.is_file():
            return False
        if path.suffix == ".py":
            return True
        with path.open("rb") as handle:
            first_line = handle.read(PEEK_BYTES).split(b"\n", 1)[0]
        return SHEBANG_RE.search(first_line) is not None
    except OSError:
        return False


def main(argv: list[str]) -> int:
    """Write the Python subset of argv to stdout, NUL-separated.

    Args:
        argv: Candidate paths.

    Returns:
        Process exit status, always 0: an empty list is a valid result.
    """
    out = "".join(f"{name}\0" for name in argv if is_python(Path(name)))
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
