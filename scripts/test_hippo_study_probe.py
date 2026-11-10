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


if __name__ == "__main__":
    unittest.main()
