#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Build the repo atlas: a derived static file explorer for this repository.

Every page the atlas renders is a function of the working tree, so the site
cannot disagree with the code it describes. Four tiers stack on each node in
order of confidence:

    T0  structure      stdlib ast, comment scans, key walks
    T1  authored prose docstrings and header comment blocks
    T2  doc binding    sentences in CLAUDE.md / README.md / docs that name the path
    T3  synthesis      model-written prose, fenced by a content hash

Tiers T0 through T2 are recomputed from scratch on every build. Only T3 can go
stale, and it is suppressed rather than rendered whenever the hash of the source
it was written from no longer matches. See docs/repo-atlas.md.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent
SITE = REPO / "site"
CACHE = SITE / "enrichment.json"

# Enrichment threshold. Both floors were set against the tree at a8792d8, where
# they produced a queue of 8 files and 30 directories out of 406 tracked files.
# Raising or lowering either is a policy change: see docs/repo-atlas.md.
LOC_FLOOR = 80
DIR_CHILD_FLOOR = 3

# Files that are real repository content but carry no authored meaning. They stay
# visible in the tree with their reason attached; they are only kept out of the
# enrichment queue.
EXCLUDE = [
    (re.compile(r"(^|/)[^/]*\.lock$"), "lockfile"),
    (re.compile(r"(^|/)package-lock\.json$"), "lockfile"),
    (re.compile(r"(^|/)LICENSE"), "licence"),
    (re.compile(r"^home/\.config/yazi/flavors/"), "vendored theme"),
    (re.compile(r"^home/\.pi/agent/themes/"), "generated theme"),
    (re.compile(r"(^|/)\.gitignore$"), "ignore list"),
    (re.compile(r"(^|/)lazy-lock\.json$"), "generated"),
]

DOC_SOURCES = ["CLAUDE.md", "README.md", "AGENTS.md"]

STDLIB_HINT = {
    "os",
    "sys",
    "re",
    "json",
    "pathlib",
    "subprocess",
    "argparse",
    "typing",
    "dataclasses",
    "collections",
    "itertools",
    "functools",
    "hashlib",
    "ast",
    "shutil",
    "tempfile",
    "textwrap",
    "datetime",
    "time",
    "math",
    "io",
    "enum",
    "sqlite3",
    "urllib",
    "logging",
    "unittest",
    "contextlib",
    "signal",
    "errno",
    "glob",
    "fnmatch",
    "socket",
    "struct",
    "base64",
    "random",
    "string",
    "csv",
    "tomllib",
    "traceback",
    "warnings",
    "abc",
    "copy",
    "uuid",
    "platform",
}
FIRST_PARTY = {"mcp_sync", "agent_reap"}


# ── inventory ────────────────────────────────────────────────────────────────


@dataclass
class Node:
    """One file or directory in the atlas.

    Attributes:
        path: Repo-relative path. The empty string is the repository root.
        kind: Either "file" or "dir".
        hash: blake2b digest of the file's bytes, or of the sorted child list
            for a directory.
        loc: Line count for a file, zero for a directory.
        size: Byte count for a file, zero for a directory.
        lang: Extractor that claimed this node, or "raw" when none did.
        excluded: Reason this node carries no authored meaning, or None.
        prose: T1 authored prose (docstring or header comment block).
        prose_line: Line the authored prose starts on.
        structure: T0 extracted facts, shaped per language.
        bindings: T2 quotes from the maintained documents.
        edges_out: Outbound edges, each a dict of target, kind and origin.
        edges_in: Inbound edges, filled after every node is built.
        children: Immediate child paths, for directories.
    """

    path: str
    kind: str
    hash: str = ""
    loc: int = 0
    size: int = 0
    lang: str = "raw"
    excluded: str | None = None
    prose: str = ""
    prose_line: int = 0
    structure: dict[str, Any] = field(default_factory=dict)
    bindings: list[dict[str, str]] = field(default_factory=list)
    edges_out: list[dict[str, str]] = field(default_factory=list)
    edges_in: list[dict[str, str]] = field(default_factory=list)
    children: list[str] = field(default_factory=list)
    source: str = ""


def digest(data: bytes) -> str:
    """Return a short stable content digest.

    Args:
        data: Raw bytes to hash.

    Returns:
        The first 16 hex characters of the blake2b digest.
    """
    return hashlib.blake2b(data, digest_size=8).hexdigest()


def tracked_files() -> list[str]:
    """List the repository's tracked files.

    Using git as the lister means .gitignore is respected without a second
    ignore mechanism, and build output never enters the site.

    Returns:
        Repo-relative paths, sorted.

    Raises:
        SystemExit: If git is unavailable or the directory is not a repository.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO), "ls-files"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f"build-site: cannot list tracked files: {exc}")
    return sorted(p for p in out.splitlines() if p)


def exclusion_for(path: str) -> str | None:
    """Return why a path carries no authored meaning, or None."""
    for pattern, reason in EXCLUDE:
        if pattern.search(path):
            return reason
    return None


def build_inventory() -> dict[str, Node]:
    """Walk the tracked tree into nodes, hashing every file.

    Returns:
        Nodes keyed by repo-relative path, including one node per directory and
        a root node keyed by the empty string.
    """
    nodes: dict[str, Node] = {"": Node(path="", kind="dir")}
    for rel in tracked_files():
        full = REPO / rel
        try:
            raw = full.read_bytes()
        except OSError:
            continue
        node = Node(path=rel, kind="file", hash=digest(raw), size=len(raw))
        node.excluded = exclusion_for(rel)
        try:
            text = raw.decode("utf-8")
            node.loc = text.count("\n") + 1
            node.source = text
        except UnicodeDecodeError:
            node.lang = "binary"
        nodes[rel] = node

        parts = rel.split("/")
        for i in range(len(parts) - 1):
            d = "/".join(parts[: i + 1])
            if d not in nodes:
                nodes[d] = Node(path=d, kind="dir")

    for path, node in nodes.items():
        if node.kind != "file":
            continue
        parent = path.rsplit("/", 1)[0] if "/" in path else ""
        nodes[parent].children.append(path)
    for path, node in nodes.items():
        if node.kind != "dir":
            continue
        parent = path.rsplit("/", 1)[0] if "/" in path else ""
        if path:
            nodes[parent].children.append(path)
    for node in nodes.values():
        if node.kind == "dir":
            node.children.sort()
            node.hash = digest("\n".join(node.children).encode())
    return nodes


# ── extract: python ──────────────────────────────────────────────────────────


def render_signature(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> str:
    """Render a function's parameter list back to source-like text."""
    a = fn.args
    parts: list[str] = []
    positional = a.posonlyargs + a.args
    defaults = list(a.defaults)
    pad = len(positional) - len(defaults)
    for i, arg in enumerate(positional):
        piece = arg.arg
        if arg.annotation is not None:
            piece += f": {ast.unparse(arg.annotation)}"
        if i >= pad:
            piece += f" = {ast.unparse(defaults[i - pad])}"
        parts.append(piece)
    if a.vararg:
        parts.append(f"*{a.vararg.arg}")
    for arg, default in zip(a.kwonlyargs, a.kw_defaults):
        piece = arg.arg
        if arg.annotation is not None:
            piece += f": {ast.unparse(arg.annotation)}"
        if default is not None:
            piece += f" = {ast.unparse(default)}"
        parts.append(piece)
    if a.kwarg:
        parts.append(f"**{a.kwarg.arg}")
    sig = f"{fn.name}({', '.join(parts)})"
    if fn.returns is not None:
        sig += f" -> {ast.unparse(fn.returns)}"
    return sig


def first_line(text: str | None) -> str:
    """Return a docstring's summary line, or the empty string."""
    if not text:
        return ""
    return text.strip().split("\n\n")[0].replace("\n", " ").strip()


def extract_python(node: Node) -> None:
    """Fill T0 and T1 for a Python file using stdlib ast."""
    node.lang = "python"
    try:
        tree = ast.parse(node.source)
    except SyntaxError as exc:
        node.structure = {"parse_error": f"{exc.msg} at line {exc.lineno}"}
        return

    doc = ast.get_docstring(tree)
    if doc:
        node.prose = doc.strip()
        node.prose_line = 1

    defs: list[dict[str, Any]] = []
    for item in tree.body:
        if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
            defs.append(
                {
                    "kind": "def",
                    "name": item.name,
                    "signature": render_signature(item),
                    "doc": first_line(ast.get_docstring(item)),
                    "line": item.lineno,
                }
            )
        elif isinstance(item, ast.ClassDef):
            methods = [
                {
                    "kind": "method",
                    "name": m.name,
                    "signature": render_signature(m),
                    "doc": first_line(ast.get_docstring(m)),
                    "line": m.lineno,
                }
                for m in item.body
                if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))
            ]
            defs.append(
                {
                    "kind": "class",
                    "name": item.name,
                    "signature": item.name,
                    "doc": first_line(ast.get_docstring(item)),
                    "line": item.lineno,
                    "methods": methods,
                }
            )

    groups: dict[str, list[str]] = {"stdlib": [], "first_party": [], "third_party": []}
    for item in ast.walk(tree):
        root = ""
        if isinstance(item, ast.Import):
            root = item.names[0].name.split(".")[0]
        elif isinstance(item, ast.ImportFrom) and item.module and item.level == 0:
            root = item.module.split(".")[0]
        if not root:
            continue
        bucket = (
            "stdlib"
            if root in STDLIB_HINT
            else "first_party"
            if root in FIRST_PARTY
            else "third_party"
        )
        if root not in groups[bucket]:
            groups[bucket].append(root)

    node.structure = {"defs": defs, "imports": groups}


# ── extract: shell ───────────────────────────────────────────────────────────

SHELL_FN = re.compile(r"^(?:function\s+)?([A-Za-z_][A-Za-z0-9_:-]*)\s*\(\)\s*\{", re.M)


def header_comment(text: str, marker: str = "#") -> tuple[str, int]:
    """Return the leading comment block and the line it starts on.

    The shebang is skipped. Scanning stops at the first line that is neither a
    comment nor blank, so only the file's own preamble is captured.

    Args:
        text: Full file contents.
        marker: Comment marker for this language.

    Returns:
        A (prose, line) pair; prose is empty when there is no header block.
    """
    lines = text.split("\n")
    i = 0
    if lines and lines[0].startswith("#!"):
        i = 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    start = i + 1
    collected: list[str] = []
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith(marker):
            collected.append(stripped.lstrip(marker).strip())
        elif not stripped and collected:
            break
        elif not stripped:
            pass
        else:
            break
        i += 1
    prose = " ".join(p for p in collected if p).strip()
    return (prose, start if prose else 0)


def extract_shell(node: Node) -> None:
    """Fill T0 and T1 for a shell script."""
    node.lang = "shell"
    text = node.source
    node.prose, node.prose_line = header_comment(text)
    shebang = text.split("\n", 1)[0] if text.startswith("#!") else ""
    node.structure = {
        "shebang": shebang,
        "strict_mode": bool(re.search(r"set\s+-euo\s+pipefail", text)),
        "functions": [
            {"name": m.group(1), "line": text[: m.start()].count("\n") + 1}
            for m in SHELL_FN.finditer(text)
        ],
    }


# ── extract: nix ─────────────────────────────────────────────────────────────

CAP_GATE = re.compile(r"\bmkIf\s+caps\.([A-Za-z_][A-Za-z0-9_]*)")
CAP_REF = re.compile(r"\bcaps\.([A-Za-z_][A-Za-z0-9_]*)")
ID_GATE = re.compile(r'identity\s*(==|!=)\s*"([a-z]+)"')


def parse_machines() -> dict[str, dict[str, Any]]:
    """Parse lib/machines.nix into the capability table.

    Returns:
        Host name to a dict with "identity" and a "caps" mapping of booleans.
        An empty dict when the file is missing or unparseable.
    """
    path = REPO / "lib" / "machines.nix"
    if not path.exists():
        return {}
    text = path.read_text()
    hosts: dict[str, dict[str, Any]] = {}
    for host_match in re.finditer(r"^\s{2}([a-z0-9-]+)\s*=\s*\{", text, re.M):
        name = host_match.group(1)
        chunk = text[host_match.end() :]
        end = chunk.find("\n  };")
        body = chunk if end < 0 else chunk[:end]
        ident = re.search(r'identity\s*=\s*"([a-z]+)"', body)
        caps: dict[str, bool] = {}
        caps_block = re.search(r"caps\s*=\s*\{(.*?)\n\s{4}\};", body, re.S)
        if caps_block:
            for key, val in re.findall(
                r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(true|false)\s*;", caps_block.group(1)
            ):
                caps[key] = val == "true"
        hosts[name] = {"identity": ident.group(1) if ident else "", "caps": caps}
    return hosts


def extract_nix(node: Node, machines: dict[str, dict[str, Any]]) -> None:
    """Fill T0 and T1 for a Nix module, resolving each gate to a host list."""
    node.lang = "nix"
    text = node.source
    node.prose, node.prose_line = header_comment(text)

    gates: list[dict[str, Any]] = []
    seen: set[str] = set()

    for match in list(CAP_GATE.finditer(text)) + list(CAP_REF.finditer(text)):
        cap = match.group(1)
        if cap in seen:
            continue
        seen.add(cap)
        known = any(cap in m["caps"] for m in machines.values())
        hosts = [h for h, m in machines.items() if m["caps"].get(cap)]
        gates.append(
            {
                "expr": f"caps.{cap}",
                "hosts": hosts,
                "line": text[: match.start()].count("\n") + 1,
                "unknown": not known,
            }
        )

    for match in ID_GATE.finditer(text):
        op, value = match.group(1), match.group(2)
        expr = f'identity {op} "{value}"'
        if expr in seen:
            continue
        seen.add(expr)
        hosts = [
            h
            for h, m in machines.items()
            if (m["identity"] == value if op == "==" else m["identity"] != value)
        ]
        gates.append(
            {
                "expr": expr,
                "hosts": hosts,
                "line": text[: match.start()].count("\n") + 1,
                "unknown": False,
            }
        )

    node.structure = {"gates": gates}


# ── extract: markdown and the rest ───────────────────────────────────────────


def extract_markdown(node: Node) -> None:
    """Fill T0 and T1 for a markdown document."""
    node.lang = "markdown"
    lines = node.source.split("\n")
    title = ""
    outline: list[dict[str, Any]] = []
    body: list[str] = []
    for i, line in enumerate(lines, 1):
        m = re.match(r"^(#{1,4})\s+(.*)", line)
        if m:
            level, heading = len(m.group(1)), m.group(2).strip()
            if level == 1 and not title:
                title = heading
            outline.append({"level": level, "text": heading, "line": i})
        elif (
            line.strip()
            and not line.startswith(("```", "|", ">", "-", "*"))
            and not body
        ):
            body.append(line.strip())
    node.prose = " ".join(body)[:400]
    node.prose_line = 1 if node.prose else 0
    node.structure = {"title": title, "outline": outline[:60]}


def extract_generic(node: Node, marker: str, lang: str) -> None:
    """Fill T0 and T1 for a comment-bearing config format."""
    node.lang = lang
    node.prose, node.prose_line = header_comment(node.source, marker)
    keys = re.findall(r"^([A-Za-z_][A-Za-z0-9_.-]*)\s*=", node.source, re.M)
    node.structure = {"keys": sorted(set(keys))[:40]}


def extract_json(node: Node) -> None:
    """Fill T0 for a JSON document by listing its top-level keys."""
    node.lang = "json"
    try:
        data = json.loads(node.source)
    except (json.JSONDecodeError, ValueError):
        node.structure = {"parse_error": "invalid JSON"}
        return
    node.structure = {"keys": sorted(data)[:40] if isinstance(data, dict) else []}


def run_extractors(nodes: dict[str, Node], machines: dict[str, dict[str, Any]]) -> None:
    """Dispatch every file node to the extractor that claims it."""
    for node in nodes.values():
        if node.kind != "file" or node.lang == "binary" or not node.source:
            continue
        name, suffix = node.path.rsplit("/", 1)[-1], Path(node.path).suffix
        shebang = node.source.split("\n", 1)[0]
        if suffix == ".py" or "python" in shebang:
            extract_python(node)
        elif (
            suffix in {".sh", ".zsh", ".bash"}
            or name.startswith(".z")
            or "sh" in shebang[:40]
        ):
            extract_shell(node)
        elif suffix == ".nix":
            extract_nix(node, machines)
        elif suffix in {".md", ".markdown"}:
            extract_markdown(node)
        elif suffix == ".json":
            extract_json(node)
        elif suffix in {".toml", ".yml", ".yaml", ".cfg", ".ini", ".conf"}:
            extract_generic(node, "#", suffix.lstrip("."))
        elif suffix == ".lua":
            extract_generic(node, "--", "lua")
        elif suffix in {".js", ".mjs", ".ts"}:
            extract_generic(node, "//", "javascript")


# ── bind: maintained prose to paths ──────────────────────────────────────────

BACKTICK = re.compile(r"`([^`\n]{2,120})`")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+")
TABLE_ROW = re.compile(r"^\s*\|")


def split_units(block: str) -> list[str]:
    """Split a markdown block into independently quotable statements.

    A bullet, a numbered item and a table row each stand alone. Flattening a
    whole block first would let one item's text trail into the quote attached
    to the next item's path, so list structure is honoured before whitespace
    is collapsed.

    Args:
        block: One blank-line-delimited markdown block.

    Returns:
        Flattened statements, each with its list marker and table pipes removed.
    """
    units: list[str] = []
    current: list[str] = []
    for line in block.split("\n"):
        if TABLE_ROW.match(line):
            if current:
                units.append(" ".join(current))
                current = []
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not all(set(c) <= {"-", ":", " "} for c in cells if c):
                units.append(" — ".join(c for c in cells if c))
            continue
        if LIST_ITEM.match(line):
            if current:
                units.append(" ".join(current))
            current = [LIST_ITEM.sub("", line).strip()]
        else:
            current.append(line.strip())
    if current:
        units.append(" ".join(current))
    return [" ".join(u.split()) for u in units if u.strip()]


def bind_docs(nodes: dict[str, Node]) -> int:
    """Attach maintained prose to the paths it names.

    Scans CLAUDE.md, README.md, AGENTS.md and docs/**.md for backticked spans
    that resolve to a node, and attaches the containing sentence with its
    nearest heading.

    Args:
        nodes: The node table, mutated in place.

    Returns:
        The number of nodes that received at least one binding.
    """
    docs = [d for d in DOC_SOURCES if (REPO / d).exists()]
    docs += sorted(str(p.relative_to(REPO)) for p in (REPO / "docs").rglob("*.md"))

    for doc in docs:
        try:
            text = (REPO / doc).read_text()
        except OSError:
            continue
        heading = ""
        for block in re.split(r"\n\s*\n", text):
            head = re.match(r"^#{1,6}\s+(.*)", block.strip())
            if head:
                heading = head.group(1).strip()
                continue
            if block.strip().startswith("```"):
                continue
            # Split list items apart before flattening. A bullet is its own
            # statement, so joining the whole block first would let one item's
            # text bleed into the quote attached to the next item's path.
            for unit in split_units(block):
                for sentence in re.split(r"(?<=[.:])\s+(?=[A-Z`])", unit):
                    hits = {
                        m.group(1).strip().rstrip("/")
                        for m in BACKTICK.finditer(sentence)
                    }
                    for hit in hits:
                        node = nodes.get(hit)
                        if node is None or not hit:
                            continue
                        quote = sentence.strip()
                        if len(quote) < 12 or len(quote) > 600:
                            continue
                        if any(b["text"] == quote for b in node.bindings):
                            continue
                        node.bindings.append(
                            {"text": quote, "doc": doc, "heading": heading}
                        )
    return sum(1 for n in nodes.values() if n.bindings)


# ── graph: edges the repository already declares ─────────────────────────────


def add_edge(nodes: dict[str, Node], src: str, dst: str, origin: str) -> None:
    """Record a directional edge when both endpoints are real nodes."""
    if src not in nodes or dst not in nodes or src == dst:
        return
    if any(e["target"] == dst and e["origin"] == origin for e in nodes[src].edges_out):
        return
    nodes[src].edges_out.append({"target": dst, "origin": origin})


SCRIPT_REF = re.compile(
    r"\b((?:scripts|home/\.local/bin|mcp_sync|agent_reap)/[\w./-]+)"
)


def build_graph(nodes: dict[str, Node]) -> int:
    """Derive edges from the Justfile, mkLinks, CI workflows and imports.

    Args:
        nodes: The node table, mutated in place.

    Returns:
        Total number of edges recorded.
    """
    for caller in ["Justfile", "bootstrap.sh", "rebuild.sh"]:
        node = nodes.get(caller)
        if node and node.source:
            for m in SCRIPT_REF.finditer(node.source):
                add_edge(nodes, caller, m.group(1), "invokes")

    dot = nodes.get("modules/home/dotfiles.nix")
    if dot and dot.source:
        for m in re.finditer(r'^\s*"([^"\n]+)"\s*(?:#.*)?$', dot.source, re.M):
            target = f"home/{m.group(1)}"
            if target in nodes:
                add_edge(nodes, "modules/home/dotfiles.nix", target, "links")

    for path, node in nodes.items():
        if path.startswith(".github/workflows/") and node.source:
            for m in SCRIPT_REF.finditer(node.source):
                add_edge(nodes, path, m.group(1), "runs in CI")

    for path, node in nodes.items():
        if node.lang == "shell" and node.source:
            for m in re.finditer(
                r"^\s*(?:source|\.)\s+\S*?([\w./-]+\.sh)", node.source, re.M
            ):
                for cand in (m.group(1), f"scripts/{Path(m.group(1)).name}"):
                    if cand in nodes:
                        add_edge(nodes, path, cand, "sources")
                        break

    for node in nodes.values():
        for edge in node.edges_out:
            nodes[edge["target"]].edges_in.append(
                {"target": node.path, "origin": edge["origin"]}
            )
    return sum(len(n.edges_out) for n in nodes.values())


# ── score: who genuinely needs a model ───────────────────────────────────────


def needs_llm(node: Node) -> str | None:
    """Return why this node needs synthesis, or None when it does not.

    A node qualifies only when every cheaper tier has already failed on it. The
    two floors are module constants so the policy is one reviewable diff.

    Args:
        node: The node to score.

    Returns:
        A short reason string, or None when the deterministic tiers suffice.
    """
    if node.kind == "dir":
        if node.path == "":
            return None
        files = [
            c
            for c in node.children
            if "/" in c and c.count("/") == node.path.count("/") + 1
        ]
        has_readme = any(Path(c).name.lower().startswith("readme") for c in files)
        if len(files) >= DIR_CHILD_FLOOR and not has_readme and not node.bindings:
            return f"{len(files)} files, no README, no doc binding"
        return None
    if node.excluded:
        return None
    if node.prose or node.bindings:
        return None
    if node.loc < LOC_FLOOR:
        return None
    return f"no prose, no doc anchor, {node.loc} lines"


# ── render ───────────────────────────────────────────────────────────────────


def load_cache() -> dict[str, dict[str, str]]:
    """Load the committed enrichment cache, or an empty one."""
    if not CACHE.exists():
        return {}
    try:
        return json.loads(CACHE.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def to_payload(nodes: dict[str, Node], machines: dict[str, Any]) -> dict[str, Any]:
    """Assemble the render payload, applying the staleness contract.

    A cached paragraph renders only when its stored source hash still matches
    the node. On a mismatch it is dropped from the payload entirely, so stale
    prose cannot reach the page by any route.

    Args:
        nodes: The fully built node table.
        machines: The parsed capability table.

    Returns:
        A JSON-serialisable payload for the client.
    """
    cache = load_cache()
    fresh = stale = missing = 0
    out: dict[str, Any] = {}

    for path, node in sorted(nodes.items()):
        reason = needs_llm(node)
        entry = cache.get(path)
        synthesis = None
        if entry:
            if entry.get("source_hash") == node.hash:
                synthesis = {
                    "text": entry.get("text", ""),
                    "commit": entry.get("commit", ""),
                }
                fresh += 1
            else:
                stale += 1
        elif reason:
            missing += 1

        record: dict[str, Any] = {
            "path": path,
            "kind": node.kind,
            "name": path.rsplit("/", 1)[-1] if path else "/",
            "hash": node.hash,
        }
        if node.kind == "file":
            record["loc"] = node.loc
            record["size"] = node.size
            record["lang"] = node.lang
            if node.source and node.lang != "binary":
                record["source"] = node.source[:60000]
        else:
            record["children"] = node.children
        if node.excluded:
            record["excluded"] = node.excluded
        if node.prose:
            record["prose"] = node.prose
            record["prose_line"] = node.prose_line
        if node.structure:
            record["structure"] = node.structure
        if node.bindings:
            record["bindings"] = node.bindings
        if node.edges_out:
            record["edges_out"] = node.edges_out
        if node.edges_in:
            record["edges_in"] = sorted(node.edges_in, key=lambda e: e["target"])
        if synthesis:
            record["synthesis"] = synthesis
        elif reason:
            record["pending"] = reason
        out[path] = record

    files = [n for n in nodes.values() if n.kind == "file"]
    stats = {
        "files": len(files),
        "dirs": sum(1 for n in nodes.values() if n.kind == "dir"),
        "with_prose": sum(1 for n in files if n.prose),
        "with_binding": sum(1 for n in files if n.bindings),
        "covered": sum(1 for n in files if n.prose or n.bindings),
        "queue_files": sum(1 for n in files if needs_llm(n)),
        "queue_dirs": sum(
            1 for n in nodes.values() if n.kind == "dir" and needs_llm(n)
        ),
        "edges": sum(len(n.edges_out) for n in nodes.values()),
        "fresh": fresh,
        "stale": stale,
        "missing": missing,
    }
    return {"nodes": out, "machines": machines, "stats": stats}


def write_site(payload: dict[str, Any]) -> None:
    """Write the payload and copy the static shell into site/."""
    SITE.mkdir(exist_ok=True)
    (SITE / "data.json").write_text(
        json.dumps(payload, indent=None, sort_keys=True, ensure_ascii=False)
    )
    assets = Path(__file__).resolve().parent / "site-assets"
    for name in ("index.html", "app.js", "style.css"):
        src = assets / name
        if src.exists():
            (SITE / name).write_text(src.read_text())


# ── cli ──────────────────────────────────────────────────────────────────────


def main() -> int:
    """Build the atlas and report tier coverage.

    Returns:
        Process exit status: 0 on success, 1 when --check finds a stale node.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when any cached summary is stale",
    )
    parser.add_argument(
        "--queue", action="store_true", help="print the enrichment queue and exit"
    )
    parser.add_argument(
        "--explain",
        action="store_true",
        help="with --queue, print why each node qualified",
    )
    args = parser.parse_args()

    machines = parse_machines()
    nodes = build_inventory()
    run_extractors(nodes, machines)
    bind_docs(nodes)
    build_graph(nodes)

    if args.queue:
        for path, node in sorted(nodes.items()):
            reason = needs_llm(node)
            if reason:
                print(
                    f"{node.kind:4}  {path}"
                    + (f"   [{reason}]" if args.explain else "")
                )
        return 0

    payload = to_payload(nodes, machines)
    write_site(payload)
    s = payload["stats"]
    pct = 100 * s["covered"] / s["files"] if s["files"] else 0
    print(
        f"atlas: {s['files']} files, {s['dirs']} dirs, {s['edges']} edges\n"
        f"  T1 prose      {s['with_prose']}\n"
        f"  T2 bindings   {s['with_binding']}\n"
        f"  covered       {s['covered']} ({pct:.1f}%)\n"
        f"  T3 queue      {s['queue_files']} files + {s['queue_dirs']} dirs\n"
        f"  cache         {s['fresh']} fresh, {s['stale']} stale, {s['missing']} missing"
    )
    if args.check and s["stale"]:
        print(
            f"build-site: {s['stale']} stale summaries; run `just site-enrich`",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
