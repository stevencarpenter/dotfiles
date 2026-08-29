#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""strip_context.py — PoC comment/docstring/doc stripper for blind code review.

Produces a scratch workspace whose files have identical line and column
numbers to the originals, with all comments, docstrings, and documentation
removed. Comment characters are replaced with spaces (never deleted) so
findings in the stripped copy cite real source locations directly.

Subcommands:
  diff  --repo DIR --base REF --out DIR   strip base+head of files changed
                                          between REF and the worktree, and
                                          emit a comment-free unified diff
  files --out DIR PATH...                 strip individual files into OUT

Documentation files (.md/.rst/.txt/.adoc) are omitted entirely. Unknown or
unparseable files are copied verbatim and flagged in manifest.json.
"""

from __future__ import annotations

import argparse
import difflib
import io
import json
import subprocess
import sys
import tokenize
from pathlib import Path

DOC_SUFFIXES = {".md", ".rst", ".txt", ".adoc", ".mdx"}
SLASH_SUFFIXES = {
    ".c", ".h", ".cc", ".cpp", ".hpp", ".cs", ".css", ".go", ".java", ".js",
    ".jsx", ".kt", ".kts", ".m", ".mm", ".proto", ".rs", ".scala", ".swift",
    ".ts", ".tsx",
}
HASH_SUFFIXES = {
    ".bash", ".cfg", ".conf", ".hcl", ".ini", ".jl", ".pl", ".properties",
    ".py", ".r", ".rb", ".sh", ".tf", ".tfvars", ".toml", ".yaml", ".yml",
    ".zsh",
}
SQL_SUFFIXES = {".sql"}
XML_SUFFIXES = {".html", ".htm", ".svg", ".vue", ".xhtml", ".xml"}


def strip_python(source: str) -> str:
    """Strip comments and docstrings from Python source, preserving positions.

    Comments become spaces. A standalone string expression statement (docstring
    or bare string constant) becomes '""' padded with blank lines. Falls back
    by raising on tokenize errors; caller copies verbatim.
    """
    lines = source.splitlines(keepends=True)

    def blank_span(srow: int, scol: int, erow: int, ecol: int, first_repl: str) -> None:
        for row in range(srow, erow + 1):
            idx = row - 1
            line = lines[idx]
            start = scol if row == srow else 0
            end = ecol if row == erow else len(line.rstrip("\n\r"))
            repl = first_repl if row == srow else ""
            pad = " " * max(0, (end - start) - len(repl))
            lines[idx] = line[:start] + repl + pad + line[end:]

    prev_significant = None
    for tok in tokenize.generate_tokens(io.StringIO(source).readline):
        if tok.type == tokenize.COMMENT:
            blank_span(*tok.start, *tok.end, "")
        elif tok.type == tokenize.STRING:
            # Standalone string statement: previous significant token opens a
            # suite or line (or start of file) — treat as docstring and blank.
            if prev_significant in (None, "NEWLINE", "INDENT", "DEDENT"):
                blank_span(*tok.start, *tok.end, '""')
        if tok.type in (tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT):
            prev_significant = tokenize.tok_name[tok.type]
        elif tok.type not in (tokenize.NL, tokenize.COMMENT):
            prev_significant = tokenize.tok_name[tok.type]
    return "".join(lines)


def strip_slash(source: str, nested_blocks: bool = False) -> str:
    """Strip // and /* */ comments from C-family source, space-preserving.

    String-aware for '\"', \"'\", and backtick template literals (escape-aware).
    nested_blocks enables Rust-style nested /* /* */ */.
    """
    out: list[str] = []
    i, n = 0, len(source)
    state = "code"  # code | line | block | str
    quote = ""
    depth = 0
    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                state = "line"
                out.append("  ")
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block"
                depth = 1
                out.append("  ")
                i += 2
                continue
            if ch in "\"'`":
                state = "str"
                quote = ch
            out.append(ch)
            i += 1
        elif state == "line":
            if ch == "\n":
                state = "code"
                out.append(ch)
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if ch == "*" and nxt == "/":
                depth -= 1
                out.append("  ")
                i += 2
                if depth == 0:
                    state = "code"
                continue
            if nested_blocks and ch == "/" and nxt == "*":
                depth += 1
                out.append("  ")
                i += 2
                continue
            out.append(ch if ch == "\n" else " ")
            i += 1
        else:  # str
            if ch == "\\" and quote != "`":
                out.append(ch + nxt)
                i += 2
                continue
            if ch == "\\":  # escapes are meaningful in templates too
                out.append(ch + nxt)
                i += 2
                continue
            if ch == quote:
                state = "code"
            elif ch == "\n" and quote != "`":
                state = "code"  # unterminated string line — bail to code
            out.append(ch)
            i += 1
    return "".join(out)


def strip_hash(source: str) -> str:
    """Strip #-comments (shell/yaml/toml/ruby/...), quote- and position-aware.

    A # opens a comment only at line start or after whitespace, outside
    quotes — so ${#var}, "a#b", and foo#bar survive.
    """
    out: list[str] = []
    for line in source.splitlines(keepends=True):
        res: list[str] = []
        state = "code"
        quote = ""
        i = 0
        while i < len(line):
            ch = line[i]
            if state == "code":
                if ch == "#" and (i == 0 or line[i - 1] in " \t"):
                    res.extend(" " if c != "\n" else c for c in line[i:])
                    break
                if ch in "\"'":
                    state = "str"
                    quote = ch
                res.append(ch)
            else:
                if ch == "\\" and quote == '"':
                    res.append(ch)
                    if i + 1 < len(line):
                        res.append(line[i + 1])
                        i += 2
                        continue
                elif ch == quote:
                    state = "code"
                res.append(ch)
            i += 1
        out.append("".join(res))
    return "".join(out)


def strip_sql(source: str) -> str:
    """Strip -- and /* */ comments from SQL, space-preserving, string-aware."""
    out: list[str] = []
    i, n = 0, len(source)
    state = "code"
    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if state == "code":
            if ch == "-" and nxt == "-":
                state = "line"
                out.append("  ")
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block"
                out.append("  ")
                i += 2
                continue
            if ch == "'":
                state = "str"
            out.append(ch)
            i += 1
        elif state == "line":
            if ch == "\n":
                state = "code"
                out.append(ch)
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if ch == "*" and nxt == "/":
                state = "code"
                out.append("  ")
                i += 2
                continue
            out.append(ch if ch == "\n" else " ")
            i += 1
        else:  # str: '' escapes a quote
            if ch == "'" and nxt == "'":
                out.append("''")
                i += 2
                continue
            if ch == "'":
                state = "code"
            out.append(ch)
            i += 1
    return "".join(out)


def strip_xml(source: str) -> str:
    """Strip <!-- --> comments, space-preserving."""
    out: list[str] = []
    i, n = 0, len(source)
    in_comment = False
    while i < n:
        if not in_comment and source.startswith("<!--", i):
            in_comment = True
            out.append("    ")
            i += 4
            continue
        if in_comment and source.startswith("-->", i):
            in_comment = False
            out.append("   ")
            i += 3
            continue
        ch = source[i]
        out.append(ch if (not in_comment or ch == "\n") else " ")
        i += 1
    return "".join(out)


def strip_source(path_name: str, source: str) -> tuple[str, str]:
    """Return (stripped_source, action) for a file by suffix."""
    suffix = Path(path_name).suffix.lower()
    try:
        if suffix == ".py":
            return strip_python(source), "stripped"
        if suffix in SLASH_SUFFIXES:
            return strip_slash(source, nested_blocks=suffix == ".rs"), "stripped"
        if suffix in HASH_SUFFIXES:
            return strip_hash(source), "stripped"
        if suffix in SQL_SUFFIXES:
            return strip_sql(source), "stripped"
        if suffix in XML_SUFFIXES:
            return strip_xml(source), "stripped"
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return source, "copied-verbatim (parse error)"
    return source, "copied-verbatim (unknown language)"


def _is_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, check=True,
    ).stdout


def process_file(rel: str, data: bytes) -> tuple[str | None, str]:
    """Return (stripped_text_or_None, action) for raw file content."""
    suffix = Path(rel).suffix.lower()
    if suffix in DOC_SUFFIXES:
        return None, "omitted-doc"
    if _is_binary(data):
        return None, "skipped-binary"
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None, "skipped-undecodable"
    return strip_source(rel, text)


def cmd_diff(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    out = Path(args.out).resolve()
    changed = [
        line for line in _git(repo, "diff", "--name-only", args.base).splitlines()
        if line.strip()
    ]
    manifest: list[dict[str, str]] = []
    diff_chunks: list[str] = []
    for rel in changed:
        head_path = repo / rel
        try:
            base_data: bytes | None = subprocess.run(
                ["git", "-C", str(repo), "show", f"{args.base}:{rel}"],
                capture_output=True, check=True,
            ).stdout
        except subprocess.CalledProcessError:
            base_data = None  # added file
        head_data = head_path.read_bytes() if head_path.exists() else None

        entry = {"path": rel, "action": ""}
        stripped_base = stripped_head = None
        for label, data, tree in (("base", base_data, "base"), ("head", head_data, "head")):
            if data is None:
                continue
            stripped, action = process_file(rel, data)
            entry["action"] = action
            if stripped is None:
                continue
            dest = out / tree / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(stripped, encoding="utf-8")
            if label == "base":
                stripped_base = stripped
            else:
                stripped_head = stripped
        manifest.append(entry)
        if entry["action"].startswith(("omitted", "skipped")):
            continue
        diff_chunks.append("".join(difflib.unified_diff(
            (stripped_base or "").splitlines(keepends=True),
            (stripped_head or "").splitlines(keepends=True),
            fromfile=f"a/{rel}", tofile=f"b/{rel}",
        )))

    out.mkdir(parents=True, exist_ok=True)
    (out / "stripped.diff").write_text("".join(diff_chunks), encoding="utf-8")
    (out / "manifest.json").write_text(
        json.dumps({"repo": str(repo), "base": args.base, "files": manifest}, indent=2),
        encoding="utf-8",
    )
    print(f"stripped {len(changed)} changed file(s) into {out}")
    print(f"review targets: {out}/head and {out}/stripped.diff")
    return 0


def cmd_files(args: argparse.Namespace) -> int:
    out = Path(args.out).resolve()
    manifest: list[dict[str, str]] = []
    for p in args.paths:
        src = Path(p)
        rel = src.name if src.is_absolute() else str(src)
        stripped, action = process_file(rel, src.read_bytes())
        manifest.append({"path": rel, "action": action})
        if stripped is not None:
            dest = out / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(stripped, encoding="utf-8")
    out.mkdir(parents=True, exist_ok=True)
    (out / "manifest.json").write_text(
        json.dumps({"files": manifest}, indent=2), encoding="utf-8"
    )
    print(f"stripped {len(args.paths)} file(s) into {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("diff", help="strip base+head of a git diff")
    d.add_argument("--repo", default=".")
    d.add_argument("--base", default="HEAD")
    d.add_argument("--out", required=True)
    d.set_defaults(func=cmd_diff)
    f = sub.add_parser("files", help="strip individual files")
    f.add_argument("--out", required=True)
    f.add_argument("paths", nargs="+")
    f.set_defaults(func=cmd_files)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
