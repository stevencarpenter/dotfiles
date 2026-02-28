import json
import runpy
import sys
from pathlib import Path

import pytest
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
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5-codex",
                    "collaboration_mode": {"settings": {"reasoning_effort": "medium"}},
                },
            },
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
    assert usage["model"] == "gpt-5-codex"
    assert usage["reasoning_effort"] == "medium"
    assert usage["pricing_model"] == "gpt-5-codex"
    assert usage["input_cost_usd"] == pytest.approx(0.0000075)
    assert usage["cached_input_cost_usd"] == 0.0000005
    assert usage["output_cost_usd"] == 0.00004
    assert usage["reasoning_output_cost_usd"] == 0.00002
    assert usage["session_total_cost_usd"] == 0.000068


def test_main_prints_latest_session_audit(tmp_path: Path, capsys) -> None:
    codex_home = tmp_path / ".codex"
    session_dir = codex_home / "sessions" / "2026" / "02" / "28"
    _write_session_file(
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
    assert "model: gpt-5.1-codex-mini" in out
    assert "reasoning_effort: low" in out
    assert "pricing_model: gpt-5.1-codex-mini" in out
    assert "session_total_cost_usd: 0.00004164" in out


def test_main_prints_json_when_requested(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-2.jsonl"
    _write_session_file(
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
    assert payload["session_id"] == "json-id"
    assert payload["input_tokens"] == 100
    assert payload["cached_input_tokens"] == 50
    assert payload["output_tokens"] == 10
    assert payload["reasoning_output_tokens"] == 4
    assert payload["total_tokens"] == 110
    assert payload["model"] == "gpt-5.2-codex"
    assert payload["reasoning_effort"] == "high"
    assert payload["pricing_model"] == "gpt-5.2-codex"
    assert payload["input_cost_usd"] == 0.0000875
    assert payload["cached_input_cost_usd"] == 0.00000875
    assert payload["output_cost_usd"] == 0.000084
    assert payload["reasoning_output_cost_usd"] == 0.000056
    assert payload["session_total_cost_usd"] == 0.00023625


def test_parse_session_usage_handles_unknown_model_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-unknown-model.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "unknown-model-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "unknown-model-v1",
                    "collaboration_mode": {"settings": {"reasoning_effort": "xhigh"}},
                },
            },
            {
                "timestamp": "2026-02-28T08:13:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 100,
                            "cached_input_tokens": 10,
                            "output_tokens": 20,
                            "reasoning_output_tokens": 5,
                            "total_tokens": 120,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == "unknown-model-v1"
    assert usage["reasoning_effort"] == "xhigh"
    assert usage["pricing_model"] == ""
    assert usage["input_cost_usd"] == 0.0
    assert usage["cached_input_cost_usd"] == 0.0
    assert usage["output_cost_usd"] == 0.0
    assert usage["reasoning_output_cost_usd"] == 0.0
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_session_usage_uses_alias_model_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-alias-model.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "alias-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5.3-codex",
                    "effort": "high",
                },
            },
            {
                "timestamp": "2026-02-28T08:14:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 1,
                            "cached_input_tokens": 0,
                            "output_tokens": 1,
                            "reasoning_output_tokens": 1,
                            "total_tokens": 2,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_session_usage(session_file)
    assert usage is not None
    assert usage["reasoning_effort"] == "high"
    assert usage["pricing_model"] == "gpt-5.2-codex"
    assert usage["session_total_cost_usd"] == 0.00001575


def test_parse_session_usage_uses_prefix_model_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-prefix-model.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "prefix-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5-codex-2026-02-14",
                    "collaboration_mode": {"settings": {"reasoning_effort": "medium"}},
                },
            },
            {
                "timestamp": "2026-02-28T08:15:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 2,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                            "reasoning_output_tokens": 0,
                            "total_tokens": 2,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_session_usage(session_file)
    assert usage is not None
    assert usage["pricing_model"] == "gpt-5-codex"
    assert usage["session_total_cost_usd"] == 0.0000025


def test_parse_session_usage_without_turn_context_has_no_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-no-turn-context.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "no-turn-context-id"}},
            {
                "timestamp": "2026-02-28T08:16:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 2,
                            "cached_input_tokens": 0,
                            "output_tokens": 1,
                            "reasoning_output_tokens": 1,
                            "total_tokens": 3,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == ""
    assert usage["pricing_model"] == ""
    assert usage["session_total_cost_usd"] == 0.0


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


def test_main_dunder_entrypoint_help(monkeypatch) -> None:
    monkeypatch.setattr(sys, "argv", ["main.py", "--help"])
    with pytest.raises(SystemExit) as excinfo:
        runpy.run_module("main", run_name="__main__")
    assert excinfo.value.code == 0
