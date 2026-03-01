"""Unit tests for pure OpenCode parser components and selection rules."""

from pathlib import Path

import pytest

from core import opencode as opencode_module
from core.opencode import choose_opencode_session_id, parse_opencode_rows


def test_parse_opencode_rows_prefers_latest_matching_cwd_and_recomputes_missing_totals() -> None:
    rows = (
        {
            "session_id": "session-match",
            "time_created": 100,
            "data": {
                "role": "assistant",
                "modelID": "model-a",
                "cost": 0.1,
                "path": {"cwd": "/workspace/repo/app", "root": "/workspace/repo"},
                "time": {"completed": "2026-02-28T08:00:00Z"},
                "tokens": {
                    "input": 10,
                    "output": 2,
                    "reasoning": 1,
                    "cache": {"read": 3, "write": 1},
                    "total": 17,
                },
            },
        },
        {
            "session_id": "session-match",
            "time_created": 150,
            "data": {
                "role": "assistant",
                "modelID": "model-b",
                "cost": 0.2,
                "path": {"cwd": "/workspace/repo/app", "root": "/workspace/repo"},
                "time": {"completed": "2026-02-28T08:10:00Z"},
                "tokens": {
                    "input": 20,
                    "output": 4,
                    "reasoning": 0,
                    "cache": {"read": 6, "write": 2},
                },
            },
        },
        {
            "session_id": "session-other",
            "time_created": 200,
            "data": {
                "role": "assistant",
                "modelID": "model-c",
                "cost": 5.0,
                "path": {"cwd": "/other/project", "root": "/other"},
                "time": {"completed": "2026-02-28T08:20:00Z"},
                "tokens": {
                    "input": 1,
                    "output": 1,
                    "reasoning": 0,
                    "cache": {"read": 0, "write": 0},
                    "total": 2,
                },
            },
        },
    )

    usage = parse_opencode_rows(rows, Path("/tmp/opencode.db"), Path("/workspace/repo"))

    assert usage is not None
    assert usage["provider"] == "opencode"
    assert usage["session_id"] == "session-match"
    assert usage["model"] == "mixed"
    assert usage["pricing_model"] == ""
    assert usage["timestamp"] == "2026-02-28T08:10:00Z"
    assert usage["input_tokens"] == 30
    assert usage["cached_input_tokens"] == 9
    assert usage["cache_creation_input_tokens"] == 3
    assert usage["output_tokens"] == 6
    assert usage["reasoning_output_tokens"] == 1
    assert usage["total_tokens"] == 49
    assert usage["cost_source"] == "provider_billed"
    assert usage["provider_billed_unit"] == "usd"
    assert usage["provider_billed_total"] == pytest.approx(0.3)
    assert usage["session_total_cost_usd"] == pytest.approx(0.3)


def test_parse_opencode_rows_matches_when_cwd_is_subdirectory_of_row_root() -> None:
    rows = (
        {
            "session_id": "session-root",
            "time_created": 100,
            "data": {
                "role": "assistant",
                "modelID": "model-a",
                "cost": 0.1,
                "path": {"cwd": "/workspace/repo", "root": "/workspace/repo"},
                "time": {"completed": "2026-02-28T08:00:00Z"},
                "tokens": {
                    "input": 10,
                    "output": 2,
                    "reasoning": 0,
                    "cache": {"read": 0, "write": 0},
                    "total": 12,
                },
            },
        },
        {
            "session_id": "session-other",
            "time_created": 200,
            "data": {
                "role": "assistant",
                "modelID": "model-b",
                "cost": 0.2,
                "path": {"cwd": "/other/project", "root": "/other"},
                "time": {"completed": "2026-02-28T08:10:00Z"},
                "tokens": {
                    "input": 20,
                    "output": 4,
                    "reasoning": 0,
                    "cache": {"read": 0, "write": 0},
                    "total": 24,
                },
            },
        },
    )

    usage = parse_opencode_rows(rows, Path("/tmp/opencode.db"), Path("/workspace/repo/app"))

    assert usage is not None
    assert usage["session_id"] == "session-root"


def test_parse_opencode_rows_falls_back_to_latest_session_when_no_cwd_match() -> None:
    rows = (
        {
            "session_id": "older",
            "time_created": 100,
            "data": {
                "role": "assistant",
                "modelID": "model-a",
                "cost": 0.1,
                "path": {"cwd": "/first", "root": "/first"},
                "time": {"completed": "2026-02-28T08:00:00Z"},
                "tokens": {
                    "input": 10,
                    "output": 1,
                    "reasoning": 0,
                    "cache": {"read": 0, "write": 0},
                    "total": 11,
                },
            },
        },
        {
            "session_id": "latest",
            "time_created": 200,
            "data": {
                "role": "assistant",
                "modelID": "model-b",
                "cost": 0.4,
                "path": {"cwd": "/second", "root": "/second"},
                "time": {"completed": "2026-02-28T08:05:00Z"},
                "tokens": {
                    "input": 20,
                    "output": 2,
                    "reasoning": 0,
                    "cache": {"read": 0, "write": 0},
                    "total": 22,
                },
            },
        },
    )

    usage = parse_opencode_rows(rows, Path("/tmp/opencode.db"), Path("/workspace/repo"))

    assert usage is not None
    assert usage["session_id"] == "latest"
    assert usage["total_tokens"] == 22


def test_parse_opencode_rows_returns_none_when_no_assistant_usage_rows_exist() -> None:
    usage = parse_opencode_rows(
        (
            {
                "session_id": "x",
                "time_created": 1,
                "data": {"role": "user", "tokens": {"input": 1}},
            },
        ),
        Path("/tmp/opencode.db"),
        Path("/workspace/repo"),
    )

    assert usage is None


def test_parse_opencode_rows_returns_none_for_assistant_rows_without_tokens() -> None:
    usage = parse_opencode_rows(
        (
            {
                "session_id": "x",
                "time_created": 1,
                "data": {"role": "assistant", "modelID": "model"},
            },
        ),
        Path("/tmp/opencode.db"),
        Path("/workspace/repo"),
    )

    assert usage is None


def test_choose_opencode_session_id_returns_empty_for_no_rows() -> None:
    assert choose_opencode_session_id((), Path("/workspace/repo")) == ""


def test_parse_opencode_rows_returns_none_when_session_id_is_empty() -> None:
    usage = parse_opencode_rows(
        (
            {
                "session_id": "",
                "time_created": 10,
                "data": {
                    "role": "assistant",
                    "modelID": "model-a",
                    "cost": 0.1,
                    "path": {"cwd": "/workspace/repo", "root": "/workspace"},
                    "tokens": {
                        "input": 1,
                        "output": 1,
                        "reasoning": 0,
                        "cache": {"read": 0, "write": 0},
                        "total": 2,
                    },
                },
            },
        ),
        Path("/tmp/opencode.db"),
        Path("/workspace/repo"),
    )

    assert usage is None


def test_is_path_prefix_handles_empty_values() -> None:
    assert opencode_module._is_path_prefix("", "/workspace/repo") is False
    assert opencode_module._is_path_prefix("/workspace/repo", "") is False


def test_is_path_prefix_root_matches_all_paths() -> None:
    assert opencode_module._normalize_path_text("/") == "/"
    assert opencode_module._is_path_prefix("/", "/workspace/repo") is True
