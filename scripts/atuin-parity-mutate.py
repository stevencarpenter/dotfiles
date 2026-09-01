#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Apply one text mutation to a throwaway copy of an atuin config.

Used only by scripts/test-atuin-filter-parity-mutations.sh, which introduces a
single regression at a time and asserts the parity guard fails with the right
message. Mutations go through Python rather than `sed -i`, whose in-place flag
takes an argument on BSD and not on GNU; this runs on both.

Usage:
    atuin-parity-mutate.py <op> <file> [args...]

Ops:
    sub <old> <new>          replace a unique substring
    delline <substring>      drop every line containing a substring
    subline <line> <new>     replace one exact line
    delexact <line>          drop one exact line
    shrink <n>               replace the history_filter block with n patterns
    addpat                   insert one extra pattern before the AKIA entry
    swap <substrA> <substrB> swap the two lines holding those substrings
    append <text>            append a line
    padto <other-file>       pad to the other file's byte size
"""

import os
import sys


def mutate(op, text, rest, path):
    """Return the mutated file text for one operation.

    Args:
        op: Operation name, one of the ops listed in the module docstring.
        text: Current file contents.
        rest: Operation arguments following the file path.
        path: File path, used only in assertion messages.

    Returns:
        The mutated contents.

    Raises:
        AssertionError: If a uniqueness precondition does not hold.
        SystemExit: If the operation name is unknown.
    """
    s = text
    if op == "sub":
        old, new = rest
        assert s.count(old) == 1, f"{path}: expected 1 occurrence of {old!r}, found {s.count(old)}"
        return s.replace(old, new)
    if op == "delline":
        needle = rest[0]
        return "\n".join(line for line in s.split("\n") if needle not in line)
    if op == "subline":
        # Line-exact, for keys whose text also appears in prose above them —
        # `auto_sync = false` is both an assignment and part of its own comment.
        old, new = rest
        lines = s.split("\n")
        hits = [i for i, line in enumerate(lines) if line == old]
        assert len(hits) == 1, f"{path}: expected 1 line == {old!r}, found {len(hits)}"
        lines[hits[0]] = new
        return "\n".join(lines)
    if op == "delexact":
        old = rest[0]
        lines = s.split("\n")
        hits = [i for i, line in enumerate(lines) if line == old]
        assert len(hits) == 1, f"{path}: expected 1 line == {old!r}, found {len(hits)}"
        return "\n".join(line for i, line in enumerate(lines) if i != hits[0])
    if op == "shrink":
        n = int(rest[0])
        lines = s.split("\n")
        b = next(i for i, line in enumerate(lines) if line.startswith("# --- BEGIN history_filter"))
        e = next(i for i, line in enumerate(lines) if line.startswith("# --- END history_filter"))
        body = ["history_filter = ["] + [f'    "PAT{i}",' for i in range(n)] + ["]"]
        return "\n".join(lines[: b + 1] + body + lines[e:])
    if op == "addpat":
        return s.replace('    "AKIA', '    "MUTATION_ONLY",\n    "AKIA', 1)
    if op == "swap":
        a, b = rest
        lines = s.split("\n")
        i = next(n for n, line in enumerate(lines) if a in line)
        j = next(n for n, line in enumerate(lines) if b in line)
        lines[i], lines[j] = lines[j], lines[i]
        return "\n".join(lines)
    if op == "append":
        return s + rest[0] + "\n"
    if op == "padto":
        other = os.path.getsize(rest[0])
        cur = len(s.encode())
        if other > cur:
            s = s + "#" + " " * (other - cur - 2) + "\n"
        return s
    raise SystemExit(f"unknown op {op}")


def main(argv):
    """Apply one mutation in place.

    Args:
        argv: Command-line arguments after the program name: op, file, args.

    Returns:
        Process exit status: 0 on success, 2 on bad usage.
    """
    if len(argv) < 2:
        print("usage: atuin-parity-mutate.py <op> <file> [args...]", file=sys.stderr)
        return 2
    op, path = argv[0], argv[1]
    with open(path) as handle:
        text = handle.read()
    with open(path, "w") as handle:
        handle.write(mutate(op, text, argv[2:], path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
