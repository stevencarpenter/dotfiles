#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Filter a list of paths down to the text files, NUL-separated on stdout.

lefthook has no equivalent of pre-commit's `types: [text]` filter: a job just
receives whatever paths matched its glob. Handing a PNG to a text fixer
corrupts it (observed on home/.config/yazi/flavors/*/preview.png during the
pre-commit -> lefthook port), so text-rewriting jobs pipe their file list
through this first.

"Text" uses git's own heuristic: no NUL byte in the first 8000 bytes. Output is
NUL-separated for `xargs -0`, so paths containing spaces survive.

Usage:
    hook-text-files.py [path...] | xargs -0 <text-only-command>
"""

import sys
from pathlib import Path

PEEK_BYTES = 8000


def is_text(path: Path) -> bool:
    """Report whether a path is a readable regular file with no NUL byte.

    Args:
        path: Candidate file.

    Returns:
        True when the file exists, is regular, and its first 8000 bytes hold
        no NUL byte; False for directories, unreadable paths, and binaries.
    """
    try:
        if not path.is_file():
            return False
        with path.open("rb") as handle:
            return b"\0" not in handle.read(PEEK_BYTES)
    except OSError:
        return False


def main(argv: list[str]) -> int:
    """Write the text-file subset of argv to stdout, NUL-separated.

    Args:
        argv: Candidate paths.

    Returns:
        Process exit status, always 0: an empty list is a valid result.
    """
    out = "".join(f"{name}\0" for name in argv if is_text(Path(name)))
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
