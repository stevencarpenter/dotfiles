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
import os
import subprocess
import sys
import tokenize
from pathlib import Path

DOC_SUFFIXES = {".md", ".rst", ".txt", ".adoc", ".mdx"}
SLASH_SUFFIXES = {
    ".c",
    ".h",
    ".cc",
    ".cpp",
    ".hpp",
    ".cs",
    ".css",
    ".go",
    ".java",
    ".js",
    ".jsx",
    ".kt",
    ".kts",
    ".m",
    ".mm",
    ".proto",
    ".rs",
    ".scala",
    ".swift",
    ".ts",
    ".tsx",
}
HASH_SUFFIXES = {
    ".bash",
    ".cfg",
    ".conf",
    ".hcl",
    ".ini",
    ".jl",
    ".nix",
    ".pl",
    ".properties",
    ".py",
    ".r",
    ".rb",
    ".sh",
    ".tf",
    ".tfvars",
    ".toml",
    ".yaml",
    ".yml",
    ".zsh",
}
# Files with no suffix whose comment syntax is still known. A dotfiles repo is
# mostly these, so falling through to copied-verbatim would leave most of a
# diff unstripped.
HASH_STEMS = {
    "Brewfile",
    "Dockerfile",
    "Justfile",
    "Makefile",
    "justfile",
    "makefile",
    ".envrc",
    ".gitignore",
    ".gitattributes",
}
SQL_SUFFIXES = {".sql"}
XML_SUFFIXES = {".html", ".htm", ".svg", ".vue", ".xhtml", ".xml"}


# Characters after which a `/` opens a regex literal rather than dividing. This
# is the standard lexical heuristic: a regex may follow an operator, a
# delimiter, or the start of input, but not a value.
_REGEX_PRECEDERS = set("(,=:[!&|?{};+-*%~^<>")
_REGEX_KEYWORDS = frozenset(
    {
        "return",
        "typeof",
        "instanceof",
        "in",
        "of",
        "new",
        "delete",
        "void",
        "throw",
        "case",
        "do",
        "else",
        "yield",
        "await",
    }
)


def _regex_allowed(out: list[str]) -> bool:
    """Report whether a `/` at this position may open a regex literal.

    Args:
        out: Output characters emitted so far, most recent last. Comment text
            has already been blanked to spaces, so it cannot influence this.

    Returns:
        True when the preceding significant token permits a regex literal.
    """
    text = "".join(out)
    stripped = text.rstrip()
    if not stripped:
        return True
    last = stripped[-1]
    if last in _REGEX_PRECEDERS:
        return True
    if last.isalnum() or last == "_":
        word = ""
        for ch in reversed(stripped):
            if ch.isalnum() or ch == "_":
                word = ch + word
            else:
                break
        return word in _REGEX_KEYWORDS
    return False


def _scan_regex(source: str, start: int) -> int:
    """Measure a regex literal beginning at ``start``.

    Args:
        source: Full source text.
        start: Index of the opening ``/``.

    Returns:
        The literal's length in characters including flags, or 0 when the text
        does not terminate as a regex on this line (in which case the caller
        falls back to comment handling).
    """
    i, n = start + 1, len(source)
    in_class = False
    while i < n:
        ch = source[i]
        if ch == "\\":
            i += 2
            continue
        if ch == "\n":
            return 0
        if in_class:
            if ch == "]":
                in_class = False
        elif ch == "[":
            in_class = True
        elif ch == "/":
            i += 1
            while i < n and (source[i].isalpha() or source[i] == "_"):
                i += 1
            return i - start
        i += 1
    return 0


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
        # Standalone string statement: previous significant token opens a
        # suite or line (or start of file) — treat as docstring and blank.
        elif tok.type == tokenize.STRING and prev_significant in (
            None,
            "NEWLINE",
            "INDENT",
            "DEDENT",
        ):
            blank_span(*tok.start, *tok.end, '""')
        # NEWLINE/INDENT/DEDENT are already excluded from NL and COMMENT, so
        # this single test covers what used to be two identical branches.
        if tok.type not in (tokenize.NL, tokenize.COMMENT):
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
    # Each entry is the unmatched-brace count for a template substitution.
    # A stack is required because braces inside an interpolation can be
    # object/block delimiters, and template literals can be nested.
    subst_braces: list[int] = []
    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if state == "code":
            # A `/` after a value is division; after an operator or delimiter it
            # opens a regex literal. Without this test `/a//b/` reads as code
            # plus a line comment and everything after the inner `//` is
            # deleted, handing the blind reviewer broken source.
            if ch == "/" and nxt not in ("/", "*") and _regex_allowed(out):
                consumed = _scan_regex(source, i)
                if consumed:
                    out.append(source[i : i + consumed])
                    i += consumed
                    continue
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
            # Braces in a template substitution are code, so only the brace
            # that opened the current `${...}` returns to the template string.
            if subst_braces:
                if ch == "{":
                    subst_braces[-1] += 1
                elif ch == "}":
                    subst_braces[-1] -= 1
                    if subst_braces[-1] == 0:
                        subst_braces.pop()
                        state = "str"
                        quote = "`"
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
            if quote == "`" and ch == "$" and nxt == "{":
                # Inside ${...} the language is code again, so a real comment
                # there would otherwise survive into the "blind" copy.
                subst_braces.append(1)
                state = "code"
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


def strip_hash(source: str, indented_strings: bool = False) -> str:
    """Strip #-comments (shell/yaml/toml/ruby/...), quote- and position-aware.

    A # opens a comment only at line start or after whitespace, outside
    quotes — so ${#var}, "a#b", and foo#bar survive.

    When ``indented_strings`` is true (Nix), ``''...''`` is a string.
    A closer is ``''`` not followed by ``'``, ``$``, or ``\\`` (Nix escapes).
    ``${...}`` interpolations are Nix code again: comments strip, braces nest,
    and an inner ``''...''`` is another indented string.
    """
    out: list[str] = []
    stack: list[str] = ["code"]
    quote = ""
    interp_depth: list[int] = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        state = stack[-1]
        if state in ("code", "nix_interp"):
            if indented_strings and ch == "'" and nxt == "'":
                stack.append("nix_indent")
                out.extend((ch, nxt))
                i += 2
                continue
            if ch == "#" and (i == 0 or source[i - 1] in " \t\n\r"):
                while i < n and source[i] != "\n":
                    out.append(" ")
                    i += 1
                continue
            if state == "nix_interp":
                if ch == "{":
                    interp_depth[-1] += 1
                elif ch == "}":
                    interp_depth[-1] -= 1
                    out.append(ch)
                    i += 1
                    if interp_depth[-1] == 0:
                        interp_depth.pop()
                        stack.pop()
                    continue
            quotes = '"' if indented_strings else "\"'"
            if ch in quotes:
                stack.append("str")
                quote = ch
            out.append(ch)
            i += 1
        elif state == "nix_indent":
            if ch == "'" and nxt == "'":
                third = source[i + 2] if i + 2 < n else ""
                if third in ("'", "$", "\\"):
                    out.extend((ch, nxt, third))
                    i += 3
                    continue
                stack.pop()
                out.extend((ch, nxt))
                i += 2
                continue
            if ch == "$" and nxt == "{":
                stack.append("nix_interp")
                interp_depth.append(1)
                out.extend((ch, nxt))
                i += 2
                continue
            out.append(ch)
            i += 1
        else:
            if ch == "\\" and quote == '"':
                out.append(ch)
                if nxt:
                    out.append(nxt)
                    i += 2
                    continue
            elif ch == quote:
                stack.pop()
            out.append(ch)
            i += 1
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
    """Strip <!-- --> comments, space-preserving, attribute-aware."""
    # A comment cannot open inside a tag's quoted attribute value, so `<!--`
    # there is ordinary text. Without the tag/attr states, `alt="see <!-- x -->"`
    # loses real content, and validate_strip cannot object: blanking to spaces
    # is exactly what a legitimate strip looks like. Every sibling stripper
    # tracks string state for the same reason.
    out: list[str] = []
    i, n = 0, len(source)
    state = "text"
    quote = ""
    while i < n:
        ch = source[i]
        if state == "text":
            if source.startswith("<!--", i):
                state = "comment"
                out.append("    ")
                i += 4
                continue
            if ch == "<":
                state = "tag"
            out.append(ch)
            i += 1
        elif state == "tag":
            if ch in ('"', "'"):
                state, quote = "attr", ch
            elif ch == ">":
                state = "text"
            out.append(ch)
            i += 1
        elif state == "attr":
            if ch == quote:
                state, quote = "tag", ""
            out.append(ch)
            i += 1
        else:  # comment
            if source.startswith("-->", i):
                state = "text"
                out.append("   ")
                i += 3
                continue
            out.append(ch if ch == "\n" else " ")
            i += 1
    return "".join(out)


def validate_strip(path_name: str, source: str, stripped: str) -> str | None:
    """Check that a strip removed only comments and kept every position.

    Every stripper blanks comment characters to spaces in place, so the output
    must be a space-mask of the input: identical length, identical line count,
    and every non-space character unchanged. A stripper that deletes code (a
    misread regex literal, a mis-tracked quote state) violates the mask and is
    caught here rather than reaching the blind reviewer as broken source.

    Args:
        path_name: Path used to pick the language-specific check.
        source: Original file text.
        stripped: Candidate stripped text.

    Returns:
        A one-line reason when the strip is unsafe, or None when it is sound.
    """
    if len(stripped) != len(source):
        return f"length changed ({len(source)} -> {len(stripped)})"
    if stripped.count("\n") != source.count("\n"):
        return "line count changed"
    for index, (before, after) in enumerate(zip(source, stripped)):
        if before != after and after != " ":
            line = source.count("\n", 0, index) + 1
            return f"character rewritten at line {line} (not blanked)"
    if Path(path_name).suffix.lower() == ".py":
        try:
            compile(source, path_name, "exec")
        except SyntaxError:
            return None  # input was already unparseable; nothing to prove
        try:
            compile(stripped, path_name, "exec")
        except SyntaxError as exc:
            return f"stripped Python no longer parses ({exc.msg})"
    return None


def strip_source(path_name: str, source: str) -> tuple[str, str]:
    """Return (stripped_source, action) for a file by suffix.

    A strip that fails validation degrades to copied-verbatim with the reason
    attached. An honestly-flagged unstripped file costs the blind arm some
    context; a silently mangled one poisons its findings.
    """
    name = Path(path_name).name
    suffix = Path(path_name).suffix.lower()
    try:
        if suffix == ".py":
            stripped, action = strip_python(source), "stripped"
        elif suffix in SLASH_SUFFIXES:
            stripped = strip_slash(source, nested_blocks=suffix == ".rs")
            action = "stripped"
        elif suffix in HASH_SUFFIXES or name in HASH_STEMS:
            stripped, action = (
                strip_hash(source, indented_strings=suffix == ".nix"),
                "stripped",
            )
        elif suffix in SQL_SUFFIXES:
            stripped, action = strip_sql(source), "stripped"
        elif suffix in XML_SUFFIXES:
            stripped, action = strip_xml(source), "stripped"
        else:
            return source, "copied-verbatim (unknown language)"
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return source, "copied-verbatim (parse error)"
    reason = validate_strip(path_name, source, stripped)
    if reason is not None:
        return source, f"copied-verbatim (strip validation failed: {reason})"
    return stripped, action


def _is_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def _git(repo: Path, *args: str) -> str:
    """Run git in ``repo`` and return stdout.

    Args:
        repo: Repository root.
        *args: Arguments passed to git.

    Returns:
        The command's stdout.

    Raises:
        SystemExit: If git fails, with its stderr as the message. A traceback
            would bury the actual cause (a bad --base, usually).
    """
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


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


def _unified_diff(base: str, head: str, rel: str) -> str:
    """Render one file's unified diff with git-compatible line termination.

    ``difflib.unified_diff`` emits a body line without a trailing newline when
    the source file had none, and it never emits git's "\\ No newline at end
    of file" marker. Joining those chunks glues the next line (and the next
    file's header) onto the previous one, producing a patch git refuses.

    Args:
        base: Stripped base text.
        head: Stripped head text.
        rel: Repository-relative path used in the headers.

    Returns:
        A diff chunk that is empty when the two sides match, and otherwise ends
        in a newline.
    """
    lines = list(
        difflib.unified_diff(
            base.splitlines(keepends=True),
            head.splitlines(keepends=True),
            fromfile=f"a/{rel}",
            tofile=f"b/{rel}",
        )
    )
    rendered: list[str] = []
    for line in lines:
        if line.endswith("\n"):
            rendered.append(line)
        else:
            rendered.append(line + "\n\\ No newline at end of file\n")
    return "".join(rendered)


def _assert_diff_applies(repo: Path, diff_path: Path) -> None:
    """Warn when the emitted patch is not one git can parse.

    The stripped diff is the primary artifact handed to the blind reviewer. A
    malformed one is not visibly broken, so check that git can parse it rather
    than trusting the generator.

    Args:
        repo: Repository the patch was generated against.
        diff_path: Path to the written patch.
    """
    if not diff_path.read_text(encoding="utf-8").strip():
        return
    # --numstat parses the patch without consulting the worktree. `apply
    # --check` would fail legitimately here: the patch is between *stripped*
    # texts, which by construction do not match the files on disk.
    result = subprocess.run(
        ["git", "-C", str(repo), "apply", "--numstat", str(diff_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(
            f"warning: {diff_path} is not a well-formed patch "
            f"({result.stderr.strip().splitlines()[:1]})",
            file=sys.stderr,
        )


def cmd_diff(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    out = Path(args.out).resolve()
    # `git diff --name-only` omits untracked files, but a newly added file is
    # part of the change under review. Dropping it silently would hand the two
    # arms different diffs, and every context-only finding on a new file would
    # be an artifact of this tool rather than of comment bias.
    tracked = _git(repo, "diff", "--name-only", args.base).splitlines()
    untracked = _git(repo, "ls-files", "--others", "--exclude-standard").splitlines()
    seen: set[str] = set()
    changed = []
    for line in [*tracked, *untracked]:
        rel = line.strip()
        if rel and rel not in seen:
            seen.add(rel)
            changed.append(rel)
    manifest: list[dict[str, str]] = []
    diff_chunks: list[str] = []
    for rel in changed:
        head_path = repo / rel
        try:
            base_data: bytes | None = subprocess.run(
                ["git", "-C", str(repo), "show", f"{args.base}:{rel}"],
                capture_output=True,
                check=True,
            ).stdout
        except subprocess.CalledProcessError:
            base_data = None  # added file
        head_data = head_path.read_bytes() if head_path.exists() else None

        entry = {"path": rel, "action": ""}
        stripped_base = stripped_head = None
        for label, data, tree in (
            ("base", base_data, "base"),
            ("head", head_data, "head"),
        ):
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
        diff_chunks.append(_unified_diff(stripped_base or "", stripped_head or "", rel))

    out.mkdir(parents=True, exist_ok=True)
    (out / "stripped.diff").write_text("".join(diff_chunks), encoding="utf-8")
    _assert_diff_applies(repo, out / "stripped.diff")
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
        # A relative path may still climb out of --out with `..`; keep every
        # written file inside the output root.
        rel = src.name if src.is_absolute() else os.path.normpath(str(src))
        if rel.startswith("..") or os.path.isabs(rel):
            rel = src.name
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


def main(argv: list[str] | None = None) -> int:
    """Parse arguments and run the requested subcommand.

    Args:
        argv: Argument list, defaulting to ``sys.argv[1:]``.

    Returns:
        Process exit status.
    """
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
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
