"""CLI and wrapper integration tests for token_auditor entrypoints."""

import json
import runpy
import sqlite3
from pathlib import Path
from typing import TypedDict

import pytest
import sys

from tests.conftest import write_session_file
from token_auditor.core.types import SessionParseError
from token_auditor.main import (
    _calculate_costs,
    _claude_project_slug,
    _format_tokens,
    _format_usd,
    _paint,
    _print_text_audit,
    _resolve_pricing_model,
    _safe_int,
    _should_use_color,
    main,
    parse_claude_session_usage,
    parse_codex_session_usage,
    parse_opencode_session_usage,
)


class OpenCodeRow(TypedDict):
    """Typed OpenCode message row used to create SQLite fixtures."""

    session_id: str
    time_created: int
    data: dict[str, object]


def write_opencode_db(path: Path, rows: list[OpenCodeRow]) -> None:
    """Create an OpenCode SQLite fixture with deterministic message rows."""
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(path))
    try:
        connection.execute(
            """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            )
            """
        )
        for index, row in enumerate(rows, start=1):
            payload = json.dumps(row["data"], sort_keys=True)
            connection.execute(
                """
                INSERT INTO message (id, session_id, time_created, time_updated, data)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    f"msg-{index}",
                    str(row["session_id"]),
                    int(row["time_created"]),
                    int(row["time_created"]),
                    payload,
                ),
            )
        connection.commit()
    finally:
        connection.close()


def test_parse_codex_session_usage_parses_file_through_wrapper(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-a.jsonl"
    write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "session-123"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5-codex",
                    "collaboration_mode": {"settings": {"reasoning_effort": "medium"}},
                },
            },
            {
                "timestamp": "2026-02-28T08:05:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 10,
                            "cached_input_tokens": 4,
                            "output_tokens": 6,
                            "reasoning_output_tokens": 2,
                            "total_tokens": 16,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["provider"] == "codex"
    assert usage["session_id"] == "session-123"


def test_parse_claude_session_usage_parses_file_through_wrapper(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-a.jsonl"
    write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-1",
                "timestamp": "2026-02-28T09:00:20Z",
                "message": {
                    "id": "m2",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 5,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 2,
                    },
                },
            },
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is not None
    assert usage["provider"] == "claude"
    assert usage["session_id"] == "claude-1"


def test_parse_opencode_session_usage_parses_file_through_wrapper(tmp_path: Path) -> None:
    db_path = tmp_path / "opencode.db"
    write_opencode_db(
        db_path,
        [
            {
                "session_id": "opencode-1",
                "time_created": 100,
                "data": {
                    "role": "assistant",
                    "modelID": "model-a",
                    "cost": 1.5,
                    "path": {"cwd": "/repo/workspace", "root": "/repo"},
                    "time": {"completed": "2026-02-28T09:00:00Z"},
                    "tokens": {
                        "input": 10,
                        "output": 2,
                        "reasoning": 0,
                        "cache": {"read": 3, "write": 1},
                        "total": 16,
                    },
                },
            },
        ],
    )

    usage = parse_opencode_session_usage(db_path, Path("/repo/workspace"))
    assert usage is not None
    assert usage["provider"] == "opencode"
    assert usage["session_id"] == "opencode-1"
    assert usage["session_total_cost_usd"] == pytest.approx(1.5)


def test_parse_wrappers_raise_on_malformed_json(tmp_path: Path) -> None:
    bad_codex = tmp_path / "codex-bad.jsonl"
    bad_codex.write_text('{"type":"session_meta"}\n{malformed\n', encoding="utf-8")

    bad_claude = tmp_path / "claude-bad.jsonl"
    bad_claude.write_text('{"sessionId":"x"}\n{malformed\n', encoding="utf-8")

    bad_opencode = tmp_path / "opencode-bad.db"
    write_opencode_db(
        bad_opencode,
        [
            {
                "session_id": "bad",
                "time_created": 1,
                "data": {
                    "role": "assistant",
                    "modelID": "model",
                    "path": {"cwd": "/tmp", "root": "/tmp"},
                    "tokens": {"input": 1, "output": 1, "cache": {"read": 0, "write": 0}, "total": 2},
                },
            }
        ],
    )
    connection = sqlite3.connect(str(bad_opencode))
    try:
        connection.execute("UPDATE message SET data = '{malformed-json' WHERE id = 'msg-1'")
        connection.commit()
    finally:
        connection.close()

    with pytest.raises(SessionParseError, match="Malformed JSON in session file"):
        parse_codex_session_usage(bad_codex)

    with pytest.raises(SessionParseError, match="Malformed JSON in session file"):
        parse_claude_session_usage(bad_claude)

    with pytest.raises(SessionParseError, match="Malformed JSON in OpenCode message row"):
        parse_opencode_session_usage(bad_opencode, Path("/tmp"))

    invalid_sqlite = tmp_path / "not-a-db.sqlite"
    invalid_sqlite.write_text("definitely not sqlite", encoding="utf-8")
    with pytest.raises(SessionParseError, match="Failed to read OpenCode database"):
        parse_opencode_session_usage(invalid_sqlite, Path("/tmp"))


def test_compatibility_wrappers_delegate_to_core_helpers(capsys) -> None:
    assert _safe_int("9") == 9
    assert _resolve_pricing_model("codex", "gpt-5-codex-2026-02-14") == "gpt-5-codex"
    costs = _calculate_costs(
        provider="claude",
        pricing_model="claude-haiku-4-5",
        reasoning_effort="",
        input_tokens=1,
        cached_input_tokens=2,
        cache_creation_input_tokens=3,
        output_tokens=4,
        reasoning_output_tokens=0,
    )
    assert costs["session_total_cost_usd"] > 0
    assert _paint("x", 108, True).startswith("\x1b[38;5;108m")
    assert _format_usd(0.1011496) == "$0.1011496"
    assert _format_tokens(12345) == "12,345 tokens"

    _print_text_audit(
        {
            "provider": "codex",
            "session_id": "abc",
            "session_file": "/tmp/s.jsonl",
            "timestamp": "2026-02-28T08:10:00Z",
            "model": "gpt-5-codex",
            "pricing_model": "gpt-5-codex",
            "reasoning_effort": "low",
            "input_tokens": 10,
            "cached_input_tokens": 0,
            "cache_creation_input_tokens": 0,
            "output_tokens": 1,
            "reasoning_output_tokens": 0,
            "total_tokens": 11,
            "input_cost_usd": 0.0000125,
            "cached_input_cost_usd": 0.0,
            "cache_creation_input_cost_usd": 0.0,
            "output_cost_usd": 0.00001,
            "reasoning_output_cost_usd": 0.0,
            "session_total_cost_usd": 0.0000225,
        }
    )
    out = capsys.readouterr().out
    assert "Codex Token Audit" in out


def test_main_prints_latest_codex_session_audit(tmp_path: Path, capsys) -> None:
    codex_home = tmp_path / ".codex"
    session_dir = codex_home / "sessions" / "2026" / "02" / "28"
    write_session_file(
        session_dir / "rollout-1.jsonl",
        [
            {"type": "session_meta", "payload": {"id": "abc"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5.1-codex-mini",
                    "collaboration_mode": {"settings": {"reasoning_effort": "low"}},
                },
            },
            {
                "timestamp": "2026-02-28T08:10:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 1042,
                            "cached_input_tokens": 11,
                            "output_tokens": 9,
                            "reasoning_output_tokens": 3,
                            "total_tokens": 1051,
                        }
                    },
                },
            },
        ],
    )

    rc = main(["--provider", "codex", "--codex-home", str(codex_home)])
    out = capsys.readouterr().out

    assert rc == 0
    assert "Codex Token Audit" in out
    assert "Session ID" in out and "abc" in out
    assert "Input Tokens" in out and "1,042 tokens" in out
    assert "Total Cost" in out and "$0.00044164" in out


def test_main_prints_latest_claude_session_audit_prefers_current_project(tmp_path: Path, capsys) -> None:
    claude_home = tmp_path / ".claude"
    cwd = tmp_path / "workspace"
    cwd.mkdir(parents=True)

    project_dir = claude_home / "projects" / _claude_project_slug(cwd)
    global_dir = claude_home / "projects" / "other-project"

    write_session_file(
        project_dir / "a.jsonl",
        [
            {
                "sessionId": "project-session",
                "timestamp": "2026-02-28T10:00:00Z",
                "message": {
                    "id": "p1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 10,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 1,
                    },
                },
            },
        ],
    )
    write_session_file(
        global_dir / "z.jsonl",
        [
            {
                "sessionId": "global-session",
                "timestamp": "2026-02-28T11:00:00Z",
                "message": {
                    "id": "g1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 999,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 0,
                    },
                },
            },
        ],
    )

    rc = main(["--provider", "claude", "--claude-home", str(claude_home), "--cwd", str(cwd)])
    out = capsys.readouterr().out

    assert rc == 0
    assert "Claude Token Audit" in out
    assert "Session ID" in out and "project-session" in out
    assert "Input Tokens" in out and "10 tokens" in out


def test_main_claude_falls_back_to_global_latest(tmp_path: Path, capsys) -> None:
    claude_home = tmp_path / ".claude"
    cwd = tmp_path / "workspace"
    cwd.mkdir(parents=True)

    global_dir = claude_home / "projects" / "fallback-project"
    write_session_file(
        global_dir / "fallback.jsonl",
        [
            {
                "sessionId": "fallback-session",
                "timestamp": "2026-02-28T11:00:00Z",
                "message": {
                    "id": "f1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 12,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 2,
                    },
                },
            },
        ],
    )

    rc = main(["--provider", "claude", "--claude-home", str(claude_home), "--cwd", str(cwd)])
    out = capsys.readouterr().out

    assert rc == 0
    assert "Session ID" in out and "fallback-session" in out


def test_main_prints_latest_opencode_session_audit(tmp_path: Path, capsys) -> None:
    db_path = tmp_path / "opencode.db"
    write_opencode_db(
        db_path,
        [
            {
                "session_id": "session-a",
                "time_created": 100,
                "data": {
                    "role": "assistant",
                    "modelID": "model-a",
                    "cost": 0.25,
                    "path": {"cwd": "/repo/workspace", "root": "/repo"},
                    "time": {"completed": "2026-02-28T10:00:00Z"},
                    "tokens": {
                        "input": 10,
                        "output": 2,
                        "reasoning": 0,
                        "cache": {"read": 3, "write": 1},
                        "total": 16,
                    },
                },
            },
            {
                "session_id": "session-b",
                "time_created": 200,
                "data": {
                    "role": "assistant",
                    "modelID": "model-b",
                    "cost": 4.0,
                    "path": {"cwd": "/other", "root": "/other"},
                    "time": {"completed": "2026-02-28T10:10:00Z"},
                    "tokens": {
                        "input": 100,
                        "output": 10,
                        "reasoning": 0,
                        "cache": {"read": 0, "write": 0},
                        "total": 110,
                    },
                },
            },
        ],
    )

    rc = main(["--provider", "opencode", "--opencode-db", str(db_path), "--cwd", "/repo/workspace"])
    out = capsys.readouterr().out

    assert rc == 0
    assert "Opencode Token Audit" in out
    assert "Session ID" in out and "session-a" in out
    assert "Total Cost" in out and "$0.25" in out
    assert "Provider Billed" in out and "$0.25" in out


def test_main_prints_json_when_requested(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-2.jsonl"
    write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "json-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5.2-codex",
                    "collaboration_mode": {"settings": {"reasoning_effort": "high"}},
                },
            },
            {
                "timestamp": "2026-02-28T08:12:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 100,
                            "cached_input_tokens": 50,
                            "output_tokens": 10,
                            "reasoning_output_tokens": 4,
                            "total_tokens": 110,
                        }
                    },
                },
            },
        ],
    )

    rc = main(["--session-file", str(session_file), "--json"])
    out = capsys.readouterr().out
    payload = json.loads(out)

    assert rc == 0
    assert payload["provider"] == "codex"
    assert payload["session_id"] == "json-id"
    assert payload["cache_creation_input_tokens"] == 0


def test_main_failure_paths(tmp_path: Path, capsys) -> None:
    rc_codex = main(["--provider", "codex", "--codex-home", str(tmp_path / ".codex")])
    err_codex = capsys.readouterr().err
    assert rc_codex == 1
    assert "No Codex session files found." in err_codex

    rc_claude = main(["--provider", "claude", "--claude-home", str(tmp_path / ".claude")])
    err_claude = capsys.readouterr().err
    assert rc_claude == 1
    assert "No Claude session files found." in err_claude

    rc_opencode = main(["--provider", "opencode", "--opencode-db", str(tmp_path / "missing-opencode.db")])
    err_opencode = capsys.readouterr().err
    assert rc_opencode == 1
    assert "OpenCode database not found" in err_opencode

    rc_copilot = main(["--provider", "copilot"])
    err_copilot = capsys.readouterr().err
    assert rc_copilot == 1
    assert "Copilot provider is not supported" in err_copilot

    missing = tmp_path / "missing.jsonl"
    rc_missing = main(["--session-file", str(missing)])
    err_missing = capsys.readouterr().err
    assert rc_missing == 1
    assert "Session file not found" in err_missing


def test_main_fails_when_session_has_no_usage_or_malformed_json(tmp_path: Path, capsys) -> None:
    no_usage = tmp_path / "rollout-empty.jsonl"
    write_session_file(no_usage, [{"type": "session_meta", "payload": {"id": "no-usage"}}])
    rc_no_usage = main(["--session-file", str(no_usage)])
    err_no_usage = capsys.readouterr().err
    assert rc_no_usage == 1
    assert "No token usage data found" in err_no_usage

    malformed = tmp_path / "rollout-malformed.jsonl"
    malformed.write_text('{"type":"session_meta","payload":{"id":"bad-json"}}\n{malformed-json\n', encoding="utf-8")
    rc_bad = main(["--session-file", str(malformed)])
    err_bad = capsys.readouterr().err
    assert rc_bad == 1
    assert "Malformed JSON in session file" in err_bad


def test_should_use_color_modes(monkeypatch) -> None:
    class FakeStream:
        def __init__(self, is_tty: bool) -> None:
            self._is_tty = is_tty

        def isatty(self) -> bool:
            return self._is_tty

    monkeypatch.setenv("TOKEN_AUDITOR_COLOR", "always")
    assert _should_use_color(FakeStream(False))

    monkeypatch.setenv("TOKEN_AUDITOR_COLOR", "never")
    assert not _should_use_color(FakeStream(True))

    monkeypatch.delenv("TOKEN_AUDITOR_COLOR", raising=False)
    monkeypatch.setenv("NO_COLOR", "1")
    assert not _should_use_color(FakeStream(True))

    monkeypatch.delenv("NO_COLOR", raising=False)
    monkeypatch.setenv("TERM", "xterm-256color")
    assert _should_use_color(FakeStream(True))

    monkeypatch.setenv("TERM", "dumb")
    assert not _should_use_color(FakeStream(True))


def test_main_dunder_entrypoint_help(monkeypatch) -> None:
    monkeypatch.setattr(sys, "argv", ["main.py", "--help"])
    sys.modules.pop("token_auditor.main", None)
    with pytest.raises(SystemExit) as excinfo:
        runpy.run_module("token_auditor.main", run_name="__main__")
    assert excinfo.value.code == 0
