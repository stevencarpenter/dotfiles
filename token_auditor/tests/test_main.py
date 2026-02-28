import inspect
import json
import re
import runpy
import sys
from collections.abc import Callable
from pathlib import Path

import _logging as token_auditor_logging
import main as token_auditor_main
import pytest
from main import _claude_project_slug, _should_use_color, main, parse_claude_session_usage, parse_codex_session_usage


def _write_session_file(path: Path, lines: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{json.dumps(line)}\n" for line in lines), encoding="utf-8")


def test_parse_codex_session_usage_uses_last_token_count_event(tmp_path: Path) -> None:
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

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["provider"] == "codex"
    assert usage["session_id"] == "session-123"
    assert usage["input_tokens"] == 10
    assert usage["cached_input_tokens"] == 4
    assert usage["cache_creation_input_tokens"] == 0
    assert usage["output_tokens"] == 6
    assert usage["reasoning_output_tokens"] == 2
    assert usage["total_tokens"] == 16
    assert usage["timestamp"] == "2026-02-28T08:05:00Z"
    assert usage["model"] == "gpt-5-codex"
    assert usage["reasoning_effort"] == "medium"
    assert usage["pricing_model"] == "gpt-5-codex"
    assert usage["input_cost_usd"] == pytest.approx(0.0000075)
    assert usage["cached_input_cost_usd"] == 0.0000005
    assert usage["cache_creation_input_cost_usd"] == 0.0
    assert usage["output_cost_usd"] == 0.00004
    assert usage["reasoning_output_cost_usd"] == 0.00002
    assert usage["session_total_cost_usd"] == 0.000068


def test_parse_codex_session_usage_handles_unknown_model_pricing(tmp_path: Path) -> None:
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

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == "unknown-model-v1"
    assert usage["reasoning_effort"] == "xhigh"
    assert usage["pricing_model"] == ""
    assert usage["input_cost_usd"] == 0.0
    assert usage["cached_input_cost_usd"] == 0.0
    assert usage["cache_creation_input_cost_usd"] == 0.0
    assert usage["output_cost_usd"] == 0.0
    assert usage["reasoning_output_cost_usd"] == 0.0
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_codex_session_usage_uses_alias_model_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-alias-model.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "alias-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5.3-codex-mini",
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

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["reasoning_effort"] == "high"
    assert usage["pricing_model"] == "gpt-5.2-codex-mini"
    assert usage["session_total_cost_usd"] == pytest.approx(0.0000036)


def test_parse_codex_session_usage_uses_prefix_model_pricing(tmp_path: Path) -> None:
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

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["pricing_model"] == "gpt-5-codex"
    assert usage["session_total_cost_usd"] == 0.0000025


def test_parse_codex_session_usage_without_turn_context_has_no_pricing(tmp_path: Path) -> None:
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

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == ""
    assert usage["pricing_model"] == ""
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_codex_session_usage_recomputes_total_tokens_when_missing(tmp_path: Path) -> None:
    session_file = tmp_path / "rollout-missing-total.jsonl"
    _write_session_file(
        session_file,
        [
            {"type": "session_meta", "payload": {"id": "missing-total-id"}},
            {
                "type": "turn_context",
                "payload": {"model": "gpt-5-codex"},
            },
            {
                "timestamp": "2026-02-28T08:17:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 2,
                            "cached_input_tokens": 1,
                            "cache_creation_input_tokens": 0,
                            "output_tokens": 3,
                            "reasoning_output_tokens": 0,
                            "total_tokens": 0,
                        }
                    },
                },
            },
        ],
    )

    usage = parse_codex_session_usage(session_file)
    assert usage is not None
    assert usage["total_tokens"] == 6


def test_parse_claude_session_usage_deduplicates_by_message_id(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-a.jsonl"
    _write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-1",
                "type": "assistant",
                "timestamp": "2026-02-28T09:00:00Z",
                "message": {
                    "id": "m1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 10,
                        "cache_read_input_tokens": 1,
                        "cache_creation_input_tokens": 2,
                        "output_tokens": 3,
                    },
                },
            },
            {
                "sessionId": "claude-1",
                "type": "assistant",
                "timestamp": "2026-02-28T09:00:10Z",
                "message": {
                    "id": "m1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 20,
                        "cache_read_input_tokens": 4,
                        "cache_creation_input_tokens": 6,
                        "output_tokens": 8,
                    },
                },
            },
            {
                "sessionId": "claude-1",
                "type": "assistant",
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
    assert usage["model"] == "claude-sonnet-4-6"
    assert usage["pricing_model"] == "claude-sonnet-4-6"
    assert usage["input_tokens"] == 25
    assert usage["cached_input_tokens"] == 4
    assert usage["cache_creation_input_tokens"] == 6
    assert usage["output_tokens"] == 10
    assert usage["reasoning_output_tokens"] == 0
    assert usage["total_tokens"] == 45
    assert usage["timestamp"] == "2026-02-28T09:00:20Z"
    assert usage["input_cost_usd"] == pytest.approx(0.000075)
    assert usage["cached_input_cost_usd"] == pytest.approx(0.0000012)
    assert usage["cache_creation_input_cost_usd"] == pytest.approx(0.0000225)
    assert usage["output_cost_usd"] == pytest.approx(0.00015)
    assert usage["reasoning_output_cost_usd"] == 0.0
    assert usage["session_total_cost_usd"] == pytest.approx(0.0002487)


def test_parse_claude_session_usage_uses_prefix_alias_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-prefix-alias.jsonl"
    _write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-prefix",
                "type": "assistant",
                "timestamp": "2026-02-28T09:05:00Z",
                "message": {
                    "id": "pfx1",
                    "model": "claude-sonnet-4-5-20250929",
                    "usage": {
                        "input_tokens": 10,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 2,
                    },
                },
            }
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == "claude-sonnet-4-5-20250929"
    assert usage["pricing_model"] == "claude-sonnet-4-6"


def test_parse_claude_session_usage_mixed_models_per_message_pricing(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-mixed.jsonl"
    _write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-mix",
                "type": "assistant",
                "timestamp": "2026-02-28T09:10:00Z",
                "message": {
                    "id": "s1",
                    "model": "claude-sonnet-4-6",
                    "usage": {
                        "input_tokens": 100,
                        "cache_read_input_tokens": 50,
                        "cache_creation_input_tokens": 25,
                        "output_tokens": 10,
                    },
                },
            },
            {
                "sessionId": "claude-mix",
                "type": "assistant",
                "timestamp": "2026-02-28T09:11:00Z",
                "message": {
                    "id": "h1",
                    "model": "claude-haiku-4-5-20251001",
                    "usage": {
                        "input_tokens": 40,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 10,
                        "output_tokens": 20,
                    },
                },
            },
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == "mixed"
    assert usage["pricing_model"] == "mixed"
    assert usage["input_tokens"] == 140
    assert usage["cached_input_tokens"] == 50
    assert usage["cache_creation_input_tokens"] == 35
    assert usage["output_tokens"] == 30
    assert usage["total_tokens"] == 255
    assert usage["session_total_cost_usd"] == pytest.approx(0.00071125)


def test_parse_claude_session_usage_missing_model_and_bad_ints(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-no-model.jsonl"
    _write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-no-model",
                "type": "assistant",
                "timestamp": "2026-02-28T09:19:00Z",
                "message": {
                    "id": "nm1",
                    "usage": {
                        "input_tokens": "bad-int",
                        "cache_read_input_tokens": 2,
                        "cache_creation_input_tokens": 3,
                        "output_tokens": 4,
                    },
                },
            }
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is not None
    assert usage["model"] == ""
    assert usage["pricing_model"] == ""
    assert usage["input_tokens"] == 0
    assert usage["cached_input_tokens"] == 2
    assert usage["cache_creation_input_tokens"] == 3
    assert usage["output_tokens"] == 4


def test_parse_claude_session_usage_unknown_model_has_zero_cost(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-unknown.jsonl"
    _write_session_file(
        session_file,
        [
            {
                "sessionId": "claude-unk",
                "type": "assistant",
                "timestamp": "2026-02-28T09:20:00Z",
                "message": {
                    "id": "u1",
                    "model": "claude-unknown-v1",
                    "usage": {
                        "input_tokens": 10,
                        "cache_read_input_tokens": 1,
                        "cache_creation_input_tokens": 2,
                        "output_tokens": 3,
                    },
                },
            }
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is not None
    assert usage["pricing_model"] == ""
    assert usage["input_cost_usd"] == 0.0
    assert usage["cached_input_cost_usd"] == 0.0
    assert usage["cache_creation_input_cost_usd"] == 0.0
    assert usage["output_cost_usd"] == 0.0
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_claude_session_usage_returns_none_when_no_usage_entries(tmp_path: Path) -> None:
    session_file = tmp_path / "claude-no-usage.jsonl"
    _write_session_file(
        session_file,
        [
            {"sessionId": "claude-empty", "type": "assistant", "message": "not-a-dict"},
            {"sessionId": "claude-empty", "type": "assistant", "message": {"id": "x1", "usage": "not-a-dict"}},
            {"sessionId": "claude-empty", "type": "assistant", "message": {"id": "x2"}},
        ],
    )

    usage = parse_claude_session_usage(session_file)
    assert usage is None


def test_main_prints_latest_codex_session_audit(tmp_path: Path, capsys) -> None:
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
    assert "\x1b[" not in out
    assert "Codex Token Audit" in out
    assert "Session ID" in out and "abc" in out
    assert "Model" in out and "gpt-5.1-codex-mini" in out
    assert "Input Tokens" in out and "1,042 tokens" in out
    assert "Total Tokens" in out and "1,051 tokens" in out
    assert "Total Cost" in out and "$0.00044164" in out


def test_main_prints_latest_claude_session_audit_prefers_current_project(tmp_path: Path, capsys) -> None:
    claude_home = tmp_path / ".claude"
    cwd = tmp_path / "workspace"
    cwd.mkdir(parents=True)

    slug = _claude_project_slug(cwd)
    project_dir = claude_home / "projects" / slug
    global_dir = claude_home / "projects" / "other-project"

    _write_session_file(
        project_dir / "a.jsonl",
        [
            {
                "sessionId": "project-session",
                "type": "assistant",
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
            }
        ],
    )
    _write_session_file(
        global_dir / "z.jsonl",
        [
            {
                "sessionId": "global-session",
                "type": "assistant",
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
            }
        ],
    )

    rc = main(
        [
            "--provider",
            "claude",
            "--claude-home",
            str(claude_home),
            "--cwd",
            str(cwd),
        ]
    )
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
    _write_session_file(
        global_dir / "fallback.jsonl",
        [
            {
                "sessionId": "fallback-session",
                "type": "assistant",
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
            }
        ],
    )

    rc = main(
        [
            "--provider",
            "claude",
            "--claude-home",
            str(claude_home),
            "--cwd",
            str(cwd),
        ]
    )
    out = capsys.readouterr().out

    assert rc == 0
    assert "Session ID" in out and "fallback-session" in out


def test_should_use_color_modes(monkeypatch) -> None:
    class FakeStream:
        """Test double that mimics a stream object exposing ``isatty`` behavior."""

        def __init__(self, is_tty: bool) -> None:
            """Store deterministic TTY capability for color-mode test scenarios.

            Args:
                is_tty (bool): Whether this fake stream should report TTY mode.

            Returns:
                None: The constructor stores state and returns no value.
            """
            self._is_tty = is_tty

        def isatty(self) -> bool:
            """Return the configured terminal capability for this fake stream.

            Returns:
                bool: ``True`` when the fake stream represents a TTY endpoint.
            """
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


def test_main_text_output_can_force_color(tmp_path: Path, capsys, monkeypatch) -> None:
    codex_home = tmp_path / ".codex"
    session_dir = codex_home / "sessions" / "2026" / "02" / "28"
    _write_session_file(
        session_dir / "rollout-color.jsonl",
        [
            {"type": "session_meta", "payload": {"id": "color-id"}},
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5-codex",
                    "collaboration_mode": {"settings": {"reasoning_effort": "low"}},
                },
            },
            {
                "timestamp": "2026-02-28T10:20:00Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": 10,
                            "cached_input_tokens": 0,
                            "output_tokens": 1,
                            "reasoning_output_tokens": 0,
                            "total_tokens": 11,
                        }
                    },
                },
            },
        ],
    )

    monkeypatch.setenv("TOKEN_AUDITOR_COLOR", "always")
    rc = main(["--provider", "codex", "--codex-home", str(codex_home)])
    out = capsys.readouterr().out

    assert rc == 0
    assert "\x1b[38;5;" in out
    assert "Input Tokens" in out and "10 tokens" in out


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
    assert payload["provider"] == "codex"
    assert payload["session_id"] == "json-id"
    assert payload["cache_creation_input_tokens"] == 0
    assert payload["cache_creation_input_cost_usd"] == 0.0


def test_main_fails_when_no_sessions_found_codex(tmp_path: Path, capsys) -> None:
    codex_home = tmp_path / ".codex"
    rc = main(["--provider", "codex", "--codex-home", str(codex_home)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "No Codex session files found." in err


def test_main_fails_when_no_sessions_found_claude(tmp_path: Path, capsys) -> None:
    claude_home = tmp_path / ".claude"
    rc = main(["--provider", "claude", "--claude-home", str(claude_home)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "No Claude session files found." in err


def test_main_fails_when_session_file_has_no_token_usage(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-empty.jsonl"
    _write_session_file(session_file, [{"type": "session_meta", "payload": {"id": "no-usage"}}])

    rc = main(["--session-file", str(session_file)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "No token usage data found" in err


def test_main_fails_when_session_file_has_malformed_json(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "rollout-malformed.jsonl"
    session_file.write_text(
        '{"type":"session_meta","payload":{"id":"bad-json"}}\n{malformed-json\n',
        encoding="utf-8",
    )

    rc = main(["--session-file", str(session_file)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "Malformed JSON in session file" in err


def test_main_fails_when_claude_session_file_has_malformed_json(tmp_path: Path, capsys) -> None:
    session_file = tmp_path / "claude-malformed.jsonl"
    session_file.write_text(
        '{"sessionId":"claude-bad","type":"assistant","message":{"id":"x","usage":{"input_tokens":1}}}\n{malformed-json\n',
        encoding="utf-8",
    )

    rc = main(["--provider", "claude", "--session-file", str(session_file)])
    err = capsys.readouterr().err

    assert rc == 1
    assert "Malformed JSON in session file" in err


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


def _assert_verbose_docstring(documented_object: object, *, min_words: int = 12) -> None:
    name = getattr(documented_object, "__qualname__", repr(documented_object))
    docstring = inspect.getdoc(documented_object)
    assert docstring, f"{name} is missing a docstring."
    assert len(docstring.split()) >= min_words, f"{name} docstring should contain at least {min_words} words to be considered verbose."


def test_main_module_classes_and_functions_have_verbose_docstrings() -> None:
    documented_objects: tuple[object, ...] = (
        token_auditor_main.SessionParseError,
        token_auditor_main.build_parser,
        token_auditor_main.parse_args,
        token_auditor_main._safe_int,
        token_auditor_main._find_latest_session_file,
        token_auditor_main._claude_project_slug,
        token_auditor_main._find_latest_claude_session_file,
        token_auditor_main._resolve_pricing_model,
        token_auditor_main._calculate_costs,
        token_auditor_main.parse_codex_session_usage,
        token_auditor_main.parse_claude_session_usage,
        token_auditor_main._should_use_color,
        token_auditor_main._paint,
        token_auditor_main._format_usd,
        token_auditor_main._format_tokens,
        token_auditor_main._print_rows,
        token_auditor_main._print_text_audit,
        token_auditor_main._resolve_session_file,
        token_auditor_main.main,
    )
    for documented_object in documented_objects:
        _assert_verbose_docstring(documented_object)


def test_logging_module_functions_have_verbose_docstrings() -> None:
    _assert_verbose_docstring(token_auditor_logging.configure)


def _assert_typed_argument_descriptions(documented_callable: Callable[..., object]) -> None:
    name = getattr(documented_callable, "__qualname__", repr(documented_callable))
    docstring = inspect.getdoc(documented_callable) or ""
    signature = inspect.signature(documented_callable)

    parameters = tuple(signature.parameters.values())
    if parameters:
        assert "Args:" in docstring, f"{name} should include an Args section."
    for parameter in parameters:
        match = re.search(rf"^\s*{re.escape(parameter.name)}\s+\(([^)]+)\):", docstring, re.MULTILINE)
        assert match, f"{name} should describe `{parameter.name}` with an explicit type."

    assert "Returns:" in docstring, f"{name} should include a Returns section."


def test_main_module_functions_include_typed_argument_descriptions() -> None:
    documented_functions: tuple[Callable[..., object], ...] = (
        token_auditor_main.build_parser,
        token_auditor_main.parse_args,
        token_auditor_main._safe_int,
        token_auditor_main._find_latest_session_file,
        token_auditor_main._claude_project_slug,
        token_auditor_main._find_latest_claude_session_file,
        token_auditor_main._resolve_pricing_model,
        token_auditor_main._calculate_costs,
        token_auditor_main.parse_codex_session_usage,
        token_auditor_main.parse_claude_session_usage,
        token_auditor_main._should_use_color,
        token_auditor_main._paint,
        token_auditor_main._format_usd,
        token_auditor_main._format_tokens,
        token_auditor_main._print_rows,
        token_auditor_main._print_text_audit,
        token_auditor_main._resolve_session_file,
        token_auditor_main.main,
    )
    for documented_function in documented_functions:
        _assert_typed_argument_descriptions(documented_function)


def test_logging_module_functions_include_typed_argument_descriptions() -> None:
    _assert_typed_argument_descriptions(token_auditor_logging.configure)
