#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Tests for the hippo effectiveness study Phase 0 probe."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import sqlite3
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from types import ModuleType

SCRIPT = Path(__file__).resolve().parent / "hippo-study-probe.py"
CUTOVER = "2026-10-28T05:47:00+00:00"
SECRET = "rm -rf ~/very-private-path"


def load_script() -> ModuleType:
    """Load the hyphenated probe script as a module.

    Returns:
        Imported script module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.
    """
    specification = importlib.util.spec_from_file_location("hippo_study_probe", SCRIPT)
    if specification is None or specification.loader is None:
        raise RuntimeError("cannot import hippo-study-probe.py")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


PROBE = load_script()
CUT = PROBE.to_epoch(CUTOVER)


def make_db(path: Path) -> None:
    """Build a small hippo-like database with mixed timestamp units.

    Args:
        path: Database file to create.
    """
    conn = sqlite3.connect(path)
    long_input = SECRET + " " + "x" * 800
    conn.executescript(
        """
        CREATE TABLE knowledge_nodes (
            id INTEGER PRIMARY KEY, created_at INTEGER, summary TEXT,
            enrichment_model TEXT);
        CREATE TABLE claude_enrichment_queue (
            id INTEGER PRIMARY KEY, status TEXT, created_at TEXT, input TEXT);
        CREATE TABLE agentic_sessions (
            id INTEGER PRIMARY KEY, start_time INTEGER, tool_calls_json TEXT);
        """
    )
    before_ms = int((CUT - 86_400) * 1000)
    after_s = int(CUT + 86_400)
    conn.executemany(
        "INSERT INTO knowledge_nodes (created_at, summary, enrichment_model) VALUES (?, ?, ?)",
        [
            (before_ms, SECRET, "qwen-8bit"),
            (before_ms, SECRET, "qwen-8bit"),
            (after_s, SECRET, "qwen-4bit"),
        ],
    )
    conn.executemany(
        "INSERT INTO claude_enrichment_queue (status, created_at, input) VALUES (?, ?, ?)",
        [
            ("done", "2026-10-20T10:00:00Z", long_input),
            ("failed", "2026-10-20T11:00:00Z", long_input),
            ("done", "2026-11-02T10:00:00Z", long_input),
            ("done", "not a date", long_input),
        ],
    )
    calls = [
        {"name": "mcp__hippo__ask", "input": {"q": SECRET}, "result": SECRET},
        {"name": "mcp__hippo__search_hybrid", "input": {"q": "x"}},
        {"name": "Bash", "input": {"command": SECRET}, "result": "ok"},
    ]
    conn.execute(
        "INSERT INTO agentic_sessions (start_time, tool_calls_json) VALUES (?, ?)",
        (before_ms, json.dumps(calls)),
    )
    conn.commit()
    conn.close()


class ProbeTests(unittest.TestCase):
    """Unit conversion, era splits, answers, and no row-text leakage."""

    def setUp(self) -> None:
        """Create the fake database."""
        self.tmp = Path(tempfile.mkdtemp())
        self.db = self.tmp / "hippo.db"
        make_db(self.db)

    def report(self) -> str:
        """Run the probe CLI and return the written report.

        Returns:
            Report text.
        """
        out = self.tmp / "probe.md"
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            code = PROBE.main(
                ["--db", str(self.db), "--out", str(out), "--cutover", CUTOVER]
            )
        self.assertEqual(code, 0)
        self.assertEqual(out.stat().st_mode & 0o777, 0o600)
        return out.read_text()

    def test_to_epoch_handles_mixed_units(self) -> None:
        """Milliseconds, seconds and ISO text map to the same instant."""
        self.assertEqual(PROBE.to_epoch(1_700_000_000_000), 1_700_000_000)
        self.assertEqual(PROBE.to_epoch(1_700_000_000), 1_700_000_000)
        self.assertEqual(PROBE.to_epoch("2023-11-14T22:13:20Z"), 1_700_000_000)
        self.assertIsNone(PROBE.to_epoch("not a date"))
        self.assertIsNone(PROBE.to_epoch(42))

    def test_answers_and_era_split(self) -> None:
        """The report answers all three questions and splits rows at the cutover."""
        text = self.report()
        self.assertIn(
            "1. Model provenance: yes, in `knowledge_nodes.enrichment_model`", text
        )
        self.assertIn(
            "2. Raw input retained (heuristic, long text columns): `claude_enrichment_queue`",
            text,
        )
        self.assertIn(
            "3. Hippo results in tool_calls_json: 1 of 2 sampled hippo calls", text
        )
        self.assertIn("| `knowledge_nodes` | 3 | `created_at` | 2 | 1 | 0 |", text)
        self.assertIn(
            "| `claude_enrichment_queue` | 4 | `created_at` | 2 | 1 | 1 |", text
        )
        self.assertIn("| `claude_enrichment_queue` | failed | 1 | 0 |", text)
        self.assertIn("`qwen-8bit` x2", text)

    def test_report_contains_no_row_text(self) -> None:
        """Summaries, inputs and tool-call payloads never reach the report."""
        self.assertNotIn("very-private-path", self.report())

    def test_database_is_opened_read_only(self) -> None:
        """Writes through the probe's connection are refused."""
        conn = PROBE.open_readonly(self.db)
        with self.assertRaises(sqlite3.OperationalError):
            conn.execute("DELETE FROM knowledge_nodes")
        conn.close()

    def test_missing_database_is_an_error(self) -> None:
        """A wrong --db path fails clearly instead of creating a database."""
        with redirect_stderr(io.StringIO()):
            code = PROBE.main(
                ["--db", str(self.tmp / "nope.db"), "--out", str(self.tmp / "o.md")]
            )
        self.assertEqual(code, 1)
        self.assertFalse((self.tmp / "nope.db").exists())


class ReviewFindingTests(unittest.TestCase):
    """Database clobbering, malformed first timestamps, empty model columns."""

    def setUp(self) -> None:
        """Create the fake database."""
        self.tmp = Path(tempfile.mkdtemp())
        self.db = self.tmp / "hippo.db"
        make_db(self.db)

    def run_probe(self, *argv: str) -> tuple[int, str]:
        """Run the probe CLI.

        Args:
            *argv: CLI arguments.

        Returns:
            Exit code and the report text (empty if none was written).
        """
        out = self.tmp / "probe.md"
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            code = PROBE.main(["--db", str(self.db), "--cutover", CUTOVER, *argv])
        return code, out.read_text() if out.exists() else ""

    def test_refuses_to_overwrite_database(self) -> None:
        """--out naming the database, a symlink to it, or its WAL is refused."""
        link = self.tmp / "link.db"
        link.symlink_to(self.db)
        before = self.db.read_bytes()
        for target in (self.db, link, Path(str(self.db) + "-wal")):
            code, _ = self.run_probe("--out", str(target))
            self.assertEqual(code, 2)
        self.assertEqual(self.db.read_bytes(), before)

    def test_malformed_first_timestamp_does_not_hide_column(self) -> None:
        """A bad first value still lets later valid timestamps date the table."""
        conn = sqlite3.connect(self.db)
        conn.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, created_at TEXT)")
        conn.executemany(
            "INSERT INTO events (created_at) VALUES (?)",
            [("garbage",), ("2026-10-20T10:00:00Z",), ("2026-11-02T10:00:00Z",)],
        )
        conn.commit()
        conn.close()
        _, text = self.run_probe("--out", str(self.tmp / "probe.md"))
        self.assertIn("| `events` | 3 | `created_at` | 1 | 1 | 1 |", text)

    def test_empty_model_column_is_not_provenance(self) -> None:
        """A model column with only NULL or blank values does not count."""
        conn = sqlite3.connect(self.db)
        conn.execute("UPDATE knowledge_nodes SET enrichment_model = NULL")
        conn.execute("UPDATE knowledge_nodes SET enrichment_model = '' WHERE id = 1")
        conn.commit()
        conn.close()
        _, text = self.run_probe("--out", str(self.tmp / "probe.md"))
        self.assertIn(
            "1. Model provenance: no; `knowledge_nodes.enrichment_model` exist but "
            "are empty",
            text,
        )


class OutputDirectoryTests(unittest.TestCase):
    """The report never changes permissions on a caller's existing directory."""

    def test_existing_parent_keeps_its_mode(self) -> None:
        """--out inside a shared 0777 directory leaves that directory 0777."""
        tmp = Path(tempfile.mkdtemp())
        db = tmp / "hippo.db"
        make_db(db)
        shared = tmp / "shared"
        shared.mkdir()
        shared.chmod(0o777)
        out = shared / "probe.md"
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            code = PROBE.main(
                ["--db", str(db), "--out", str(out), "--cutover", CUTOVER]
            )
        self.assertEqual(code, 0)
        self.assertEqual(shared.stat().st_mode & 0o777, 0o777)
        self.assertEqual(out.stat().st_mode & 0o777, 0o600)

    def test_created_parent_is_private(self) -> None:
        """A directory the probe creates for --out is 0700."""
        tmp = Path(tempfile.mkdtemp())
        db = tmp / "hippo.db"
        make_db(db)
        out = tmp / "new" / "probe.md"
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            PROBE.main(["--db", str(db), "--out", str(out), "--cutover", CUTOVER])
        self.assertEqual(out.parent.stat().st_mode & 0o777, 0o700)


class SecondReviewTests(unittest.TestCase):
    """Free-text model columns, hard links, and replaced report modes."""

    def setUp(self) -> None:
        """Create the fake database."""
        self.tmp = Path(tempfile.mkdtemp())
        self.db = self.tmp / "hippo.db"
        make_db(self.db)

    def run_probe(self, out: Path) -> int:
        """Run the probe CLI writing to ``out``.

        Args:
            out: Report path.

        Returns:
            Exit code.
        """
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return PROBE.main(
                ["--db", str(self.db), "--out", str(out), "--cutover", CUTOVER]
            )

    def test_free_text_model_values_are_redacted(self) -> None:
        """Prompt-like text in a model column is counted, never shown."""
        conn = sqlite3.connect(self.db)
        conn.execute(
            "UPDATE knowledge_nodes SET enrichment_model = ? WHERE id = 1",
            (SECRET,),
        )
        conn.commit()
        conn.close()
        out = self.tmp / "probe.md"
        self.assertEqual(self.run_probe(out), 0)
        text = out.read_text()
        self.assertNotIn("very-private-path", text)
        self.assertIn("(redacted: not model identifiers) x1", text)
        self.assertIn("`qwen-8bit` x1", text)

    def test_refuses_hard_link_to_database(self) -> None:
        """A hard link to the database is caught by inode, not by name."""
        link = self.tmp / "hard.md"
        os.link(self.db, link)
        before = self.db.read_bytes()
        self.assertEqual(self.run_probe(link), 2)
        self.assertEqual(self.db.read_bytes(), before)

    def test_replaced_report_is_private(self) -> None:
        """An existing 0644 report is rewritten as 0600."""
        out = self.tmp / "probe.md"
        out.write_text("old")
        out.chmod(0o644)
        self.assertEqual(self.run_probe(out), 0)
        self.assertEqual(out.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
