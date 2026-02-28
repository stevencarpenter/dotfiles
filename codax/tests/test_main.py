import json
from pathlib import Path

from main import main, parse_session_usage


def _write_session_file(path: Path, lines: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{json.dumps(line)}\n" for line in lines), encoding="utf-8")


def test_parse_session_usage_uses_last_token_count_event(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-a.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "session-123"}},
            {
                "timestamp": "2026-02-28T08:00:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 1,
                            "cached_input_tokens": 0,
                            "output_tokens": 2,
                            "reasoning_output_tokens": 1,
                            "total_tokens": 3,
                        }
                    },
                },
            },
            {"type": "event_msg", "payload": {"type": "tool_call"}},
            {"type": "event_msg", "payload": {"type": "token_count", "info": {}}},
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

    usage = parse_session_usage(session_file)
    assert usage is not None
    assert usage["session_id"] == "session-123"
    assert usage["input_tokens"] == 10
    assert usage["cached_input_tokens"] == 4
    assert usage["output_tokens"] == 6
    assert usage["reasoning_output_tokens"] == 2
    assert usage["total_tokens"] == 16
    assert usage["timestamp"] == "2026-02-28T08:05:00Z"


def test_main_prints_latest_session_audit(tmp_path: Path, capsys) -> None:
    codex_home = tmp_path / ".codex"
    session_dir = codex_home / "sessions" / "2026" / "02" / "28"
    _write_session_file(
        session_dir / "rollout-1.jsonl",
        [
            {"type": "session_meta", "payload": {"id": "abc"}},
            {
                "timestamp": "2026-02-28T08:10:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 42,
                            "cached_input_tokens": 11,
                            "output_tokens": 9,
                            "reasoning_output_tokens": 3,
                            "total_tokens": 51,
                        }
                    },
                },
            },
        ],
    )

    rc = main(["--codex-home", str(codex_home)])
    out = capsys.readouterr().out

    assert rc == 0
    assert "session_id: abc" in out
    assert "input_tokens: 42" in out
    assert "cached_input_tokens: 11" in out
    assert "output_tokens: 9" in out
    assert "reasoning_output_tokens: 3" in out
    assert "total_tokens: 51" in out


def test_main_prints_json_when_requested(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-2.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "json-id"}},
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
    assert payload["session_id"] == "json-id"
    assert payload["input_tokens"] == 100
    assert payload["cached_input_tokens"] == 50
    assert payload["output_tokens"] == 10
    assert payload["reasoning_output_tokens"] == 4
    assert payload["total_tokens"] == 110


def test_main_fails_when_no_sessions_found(tmp_path: Path, capsys) -> None:
    codex_home = tmp_path / ".codex"
    rc = main(["--codex-home", str(codex_home)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "No Codex session files found." in err


def test_main_fails_when_session_file_has_no_token_count(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-empty.jsonl"
    _write_session_file(session_file, [{"type": "session_meta", "payload": {"id": "no-usage"}}])

    rc = main(["--session-file", str(session_file)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "No token usage data found" in err


def test_main_fails_when_session_file_does_not_exist(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "missing.jsonl"
    rc = main(["--session-file", str(session_file)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "Session file not found" in err
