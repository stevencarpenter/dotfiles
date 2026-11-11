#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Phase 0 probe for the hippo effectiveness study.

Answers, from ``hippo.db`` alone, the questions that decide which study phases
are possible (see ``docs/ai-tools/hippo-effectiveness-study.md``):

1. Does any table record which model enriched a row? (model provenance)
2. Are enrichment inputs retained, so old rows can be re-enriched? (raw input)
3. Does ``agentic_sessions.tool_calls_json`` keep hippo's responses, or only
   the calls? (downstream analysis)
4. How many rows fall on each side of the 8-bit -> 4-bit cutover, and how did
   each enrichment queue's statuses split? (power of the before/after look)

The database is opened read-only. The report holds schema names, counts, key
names and the distinct values of model-like columns, never row text, so it is
safe to paste into a chat or an issue. It is written 0600 under
``~/.local/share/hippo/model-eval/study/``.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any

DEFAULT_DB = Path.home() / ".local/share/hippo/hippo.db"
DEFAULT_OUT = Path.home() / ".local/share/hippo/model-eval/study/probe.md"
# The 4-bit switch was first committed in bcdf7da at 2026-10-27 23:47 -06:00 on
# the checkout the config symlinks into; #246 re-landed it on main at 03:33.
# The brain applies a config change on restart, so pass --cutover with the
# restart time when it is known.
DEFAULT_CUTOVER = "2026-10-28T05:47:00+00:00"
TIME_COLUMN = re.compile(r"(^|_)(created|updated|start|end|time|ts|at|timestamp)", re.I)
MODEL_COLUMN = re.compile(r"model", re.I)
# Queue statuses are expected to be short enum labels; anything else might be
# diagnostic text and is counted under one placeholder instead of shown.
STATUS_LABEL = re.compile(r"[A-Za-z][A-Za-z0-9_-]{0,31}")
OTHER_STATUS = "(other: not a status label)"
RESULT_KEYS = ("result", "output", "response", "content", "tool_result")
LONG_TEXT_CHARS = 500
TOOL_CALL_SAMPLE = 500
TOP_VALUES = 10
TIME_SAMPLE = 50
MODEL_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,119}")


def quote(name: str) -> str:
    """Quote an SQLite identifier.

    Args:
        name: Table or column name.

    Returns:
        The identifier in double quotes, with embedded quotes doubled.
    """
    return '"' + name.replace('"', '""') + '"'


def open_readonly(path: Path) -> sqlite3.Connection:
    """Open an SQLite database without any possibility of writing to it.

    Args:
        path: Database file.

    Returns:
        A read-only connection.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    if not path.exists():
        raise FileNotFoundError(path)
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def to_epoch(value: Any) -> float | None:
    """Interpret a stored timestamp as epoch seconds.

    Hippo mixes units (``agentic_sessions`` stores epoch milliseconds), so
    magnitude decides: above 1e11 is milliseconds, above 1e8 is seconds.

    Args:
        value: A cell from a time-like column.

    Returns:
        Epoch seconds, or None when the value is not a recognizable time.
    """
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if value > 1e14:
            return value / 1e6
        if value > 1e11:
            return value / 1000
        if value > 1e8:
            return float(value)
        return None
    if isinstance(value, str) and value:
        text = value.strip().replace("Z", "+00:00")
        try:
            stamp = dt.datetime.fromisoformat(text)
        except ValueError:
            return None
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=dt.UTC)
        return stamp.timestamp()
    return None


def tables(conn: sqlite3.Connection) -> list[str]:
    """List user tables.

    Args:
        conn: Database connection.

    Returns:
        Table names, sorted.
    """
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    return [row[0] for row in rows]


def columns(conn: sqlite3.Connection, table: str) -> list[tuple[str, str]]:
    """List a table's columns.

    Args:
        conn: Database connection.
        table: Table name.

    Returns:
        ``(name, declared_type)`` pairs.
    """
    return [(r[1], r[2]) for r in conn.execute(f"PRAGMA table_info({quote(table)})")]


def time_column(conn: sqlite3.Connection, table: str) -> str | None:
    """Pick the column that best dates a table's rows.

    Prefers a creation time, then any time-like column whose values parse.

    Args:
        conn: Database connection.
        table: Table name.

    Returns:
        Column name, or None when no column holds recognizable times.
    """
    names = [name for name, _ in columns(conn, table) if TIME_COLUMN.search(name)]
    names.sort(key=lambda n: (not n.lower().startswith(("created", "start")), n))
    for name in names:
        # Sample several values so one malformed row cannot hide a usable column.
        rows = conn.execute(
            f"SELECT {quote(name)} FROM {quote(table)} "
            f"WHERE {quote(name)} IS NOT NULL LIMIT {TIME_SAMPLE}"
        )
        if any(to_epoch(value) is not None for (value,) in rows):
            return name
    return None


def era_counts(
    conn: sqlite3.Connection, table: str, column: str, cutover: float
) -> tuple[int, int, int]:
    """Count rows before and after the cutover.

    Args:
        conn: Database connection.
        table: Table name.
        column: Time column.
        cutover: Cutover as epoch seconds.

    Returns:
        ``(before, after, undated)``.
    """
    before = after = undated = 0
    for (value,) in conn.execute(f"SELECT {quote(column)} FROM {quote(table)}"):
        epoch = to_epoch(value)
        if epoch is None:
            undated += 1
        elif epoch < cutover:
            before += 1
        else:
            after += 1
    return before, after, undated


def model_values(
    conn: sqlite3.Connection, table: str, column: str
) -> list[tuple[str, int]]:
    """Most frequent values of a model-like column.

    Args:
        conn: Database connection.
        table: Table name.
        column: Model-like column.

    Only values shaped like a model identifier are shown. Anything else (a
    column that happens to hold prompts or responses) is counted, not shown,
    so the report stays free of row text.

    Returns:
        ``(value, count)`` pairs, most frequent first, with free text folded
        into one ``(redacted)`` entry.
    """
    rows = conn.execute(
        f"SELECT {quote(column)}, COUNT(*) FROM {quote(table)} "
        f"WHERE {quote(column)} IS NOT NULL GROUP BY 1 ORDER BY 2 DESC"
    )
    shown: list[tuple[str, int]] = []
    redacted = 0
    for value, count in rows:
        text = str(value)
        if MODEL_ID.fullmatch(text) and len(shown) < TOP_VALUES:
            shown.append((text, count))
        elif not MODEL_ID.fullmatch(text):
            redacted += count
    if redacted:
        shown.append(("(redacted: not model identifiers)", redacted))
    return shown


def populated(conn: sqlite3.Connection, table: str, column: str) -> bool:
    """Check whether any row holds a non-empty value in a column.

    Args:
        conn: Database connection.
        table: Table name.
        column: Column name.

    Returns:
        True when at least one value is neither NULL nor blank.
    """
    row = conn.execute(
        f"SELECT 1 FROM {quote(table)} WHERE {quote(column)} IS NOT NULL "
        f"AND TRIM(CAST({quote(column)} AS TEXT)) != '' LIMIT 1"
    ).fetchone()
    return row is not None


def overwrites_database(out: Path, db: Path) -> bool:
    """Check whether writing the report would clobber the database.

    Covers the database file itself and SQLite's sidecar files (``-wal``,
    ``-shm``, ``-journal``), reached by path, symlink or hard link: existing
    files are compared by device and inode, not by name.

    Args:
        out: Report path.
        db: Database path.

    Returns:
        True when ``out`` is the database or one of its sidecars.
    """
    base = db.resolve()
    guarded = [base] + [
        base.with_name(base.name + s) for s in ("-wal", "-shm", "-journal")
    ]
    if out.resolve() in guarded:
        return True
    if not out.exists():
        return False
    return any(path.exists() and os.path.samefile(out, path) for path in guarded)


def long_text_columns(conn: sqlite3.Connection, table: str) -> list[tuple[str, int]]:
    """Find text columns long enough to hold raw enrichment input.

    Args:
        conn: Database connection.
        table: Table name.

    Returns:
        ``(column, average_length)`` for columns averaging over the threshold.
    """
    found = []
    for name, declared in columns(conn, table):
        if declared and not re.search(r"text|char|clob|json|blob", declared, re.I):
            continue
        # Every non-blank row, not a leading sample: retained inputs may exist
        # only in recent rows.
        row = conn.execute(
            f"SELECT AVG(LENGTH({quote(name)})) FROM {quote(table)} "
            f"WHERE {quote(name)} IS NOT NULL AND {quote(name)} != ''"
        ).fetchone()
        if row and row[0] and row[0] > LONG_TEXT_CHARS:
            found.append((name, int(row[0])))
    return found


def hippo_tool_calls(conn: sqlite3.Connection) -> dict[str, Any]:
    """Check whether recorded hippo tool calls keep their results.

    Args:
        conn: Database connection.

    Returns:
        Counts of hippo calls sampled, the keys they carry, and how many have a
        non-empty result-like field. Empty when the table or column is absent.
    """
    if "agentic_sessions" not in tables(conn):
        return {}
    if "tool_calls_json" not in {n for n, _ in columns(conn, "agentic_sessions")}:
        return {}
    calls = with_result = 0
    keys: dict[str, int] = {}
    rows = conn.execute(
        "SELECT tool_calls_json FROM agentic_sessions "
        "WHERE tool_calls_json LIKE '%mcp__hippo__%' "
        f"ORDER BY rowid DESC LIMIT {TOOL_CALL_SAMPLE}"
    )
    for (raw,) in rows:
        try:
            entries = json.loads(raw)
        except (TypeError, ValueError):
            continue
        for entry in entries if isinstance(entries, list) else []:
            if not isinstance(entry, dict):
                continue
            if not str(entry.get("name", "")).startswith("mcp__hippo__"):
                continue
            calls += 1
            for key in entry:
                keys[key] = keys.get(key, 0) + 1
            if any(entry.get(key) for key in RESULT_KEYS):
                with_result += 1
    return {"calls": calls, "keys": keys, "with_result": with_result}


def status_by_era(
    conn: sqlite3.Connection, table: str, column: str, cutover: float
) -> dict[str, list[int]]:
    """Split a queue's status counts at the cutover.

    Args:
        conn: Database connection.
        table: Queue table with a ``status`` column.
        column: Time column.
        cutover: Cutover as epoch seconds.

    Returns:
        Status to ``[before, after]`` counts. A value that is not a short
        status label is counted under ``OTHER_STATUS``, never shown.
    """
    split: dict[str, list[int]] = {}
    rows = conn.execute(f"SELECT status, {quote(column)} FROM {quote(table)}")
    for status, value in rows:
        epoch = to_epoch(value)
        if epoch is None:
            continue
        label = str(status)
        if not STATUS_LABEL.fullmatch(label):
            label = OTHER_STATUS
        counts = split.setdefault(label, [0, 0])
        counts[0 if epoch < cutover else 1] += 1
    return split


def build_report(conn: sqlite3.Connection, cutover: float, cutover_label: str) -> str:
    """Assemble the probe report.

    Args:
        conn: Read-only database connection.
        cutover: Cutover as epoch seconds.
        cutover_label: Cutover as given, for the report header.

    Returns:
        Markdown report text.
    """
    names = tables(conn)
    lines = [
        "# Hippo study probe",
        "",
        f"Cutover: `{cutover_label}`. Counts only; no row text is included.",
        "",
        "## Answers",
        "",
    ]
    model_columns = [
        (table, name)
        for table in names
        for name, _ in columns(conn, table)
        if MODEL_COLUMN.search(name)
    ]
    # A model column only counts as provenance if some row actually fills it.
    provenance = [
        (table, name) for table, name in model_columns if populated(conn, table, name)
    ]
    empty_models = [pair for pair in model_columns if pair not in provenance]
    hippo = hippo_tool_calls(conn)
    raw_inputs = {table: long_text_columns(conn, table) for table in names}
    if provenance:
        answer = "yes, in " + ", ".join(f"`{t}.{c}`" for t, c in provenance)
    elif empty_models:
        answer = (
            "no; "
            + ", ".join(f"`{t}.{c}`" for t, c in empty_models)
            + " exist but are empty, so eras come from timestamps only"
        )
    else:
        answer = "no model column; eras come from timestamps only"
    lines.append("1. Model provenance: " + answer)
    retained = [t for t, cols in raw_inputs.items() if cols]
    lines.append(
        "2. Raw input retained (heuristic, long text columns): "
        + (", ".join(f"`{t}`" for t in retained) if retained else "none found")
    )
    if hippo:
        lines.append(
            f"3. Hippo results in tool_calls_json: {hippo['with_result']} of "
            f"{hippo['calls']} sampled hippo calls carry a result-like field"
        )
    else:
        lines.append("3. Hippo results: `agentic_sessions.tool_calls_json` not found")
    lines += [
        "",
        "## Tables",
        "",
        "| table | rows | dated by | before | after | undated |",
    ]
    lines.append("|---|---|---|---|---|---|")
    queues = []
    for table in names:
        total = conn.execute(f"SELECT COUNT(*) FROM {quote(table)}").fetchone()[0]
        column = time_column(conn, table)
        if column:
            before, after, undated = era_counts(conn, table, column, cutover)
            lines.append(
                f"| `{table}` | {total} | `{column}` | {before} | {after} | {undated} |"
            )
            if "status" in {n for n, _ in columns(conn, table)} and "queue" in table:
                queues.append((table, column))
        else:
            lines.append(f"| `{table}` | {total} | - | - | - | - |")
    if queues:
        lines += ["", "## Enrichment queue status by era", ""]
        lines += ["| queue | status | before | after |", "|---|---|---|---|"]
        for table, column in queues:
            for status, (before, after) in sorted(
                status_by_era(conn, table, column, cutover).items()
            ):
                lines.append(f"| `{table}` | {status} | {before} | {after} |")
    if provenance:
        lines += ["", "## Model column values", ""]
        for table, column in provenance:
            values = ", ".join(
                f"{v} x{n}" if v.startswith("(") else f"`{v}` x{n}"
                for v, n in model_values(conn, table, column)
            )
            lines.append(f"- `{table}.{column}`: {values}")
    if hippo:
        keys = ", ".join(f"`{k}` x{n}" for k, n in sorted(hippo["keys"].items()))
        lines += ["", "## Hippo tool-call keys", "", keys or "(none)"]
    lines += ["", "## Long text columns", ""]
    for table, cols in raw_inputs.items():
        if cols:
            lines.append(
                f"- `{table}`: " + ", ".join(f"`{c}` (avg {n} chars)" for c, n in cols)
            )
    lines += ["", "## Schema", ""]
    for table in names:
        lines.append(
            f"- `{table}`: "
            + ", ".join(f"{n} {t}".strip() for n, t in columns(conn, table))
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    """Entry point.

    Args:
        argv: Arguments, defaulting to ``sys.argv[1:]``.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--cutover", default=DEFAULT_CUTOVER, help="ISO 8601 time")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    cutover = to_epoch(args.cutover)
    if cutover is None:
        print(f"cannot parse --cutover {args.cutover!r}", file=sys.stderr)
        return 2
    if overwrites_database(args.out, args.db):
        print(f"--out {args.out} would overwrite the database", file=sys.stderr)
        return 2
    try:
        conn = open_readonly(args.db)
    except FileNotFoundError:
        print(f"no database at {args.db}", file=sys.stderr)
        return 1
    with conn:
        report = build_report(conn, cutover, args.cutover)
    # Only a directory this probe creates (or its own default) is locked down;
    # a caller's existing directory, such as /tmp, keeps its permissions.
    if not args.out.parent.exists():
        args.out.parent.mkdir(mode=0o700, parents=True)
    elif args.out.parent.resolve() == DEFAULT_OUT.parent.resolve():
        args.out.parent.chmod(0o700)
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    # O_CREAT's mode applies only to a new file; an existing report keeps its
    # old mode unless it is set explicitly.
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(report)
    print(report)
    print(f"written: {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
