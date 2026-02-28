"""Unit tests for pure Claude parser components and aggregation rules."""

from pathlib import Path

import pytest
from core.claude import aggregate_claude_usage, extract_claude_message_snapshot, parse_claude_events, reduce_message_snapshots


def test_extract_claude_message_snapshot_returns_none_without_usage_mapping() -> None:
    assert extract_claude_message_snapshot({"message": {"id": "x", "usage": "bad"}}, 1) is None
    assert extract_claude_message_snapshot({"message": "bad"}, 1) is None


def test_extract_claude_message_snapshot_uses_line_fallback_id_when_missing() -> None:
    snapshot = extract_claude_message_snapshot(
        {
            "timestamp": "2026-02-28T09:00:00Z",
            "message": {
                "model": "claude-sonnet-4-6",
                "usage": {
                    "input_tokens": 10,
                    "cache_read_input_tokens": 2,
                    "cache_creation_input_tokens": 3,
                    "output_tokens": 4,
                },
            },
        },
        17,
    )

    assert snapshot is not None
    assert snapshot.message_id == "line-17"
    assert snapshot.usage.input_tokens == 10


def test_reduce_message_snapshots_keeps_latest_per_message_id() -> None:
    first = extract_claude_message_snapshot(
        {"timestamp": "t1", "message": {"id": "m1", "model": "claude-sonnet-4-6", "usage": {"input_tokens": 1}}},
        1,
    )
    second = extract_claude_message_snapshot(
        {"timestamp": "t2", "message": {"id": "m1", "model": "claude-sonnet-4-6", "usage": {"input_tokens": 5}}},
        2,
    )
    assert first is not None
    assert second is not None

    deduped = reduce_message_snapshots((first, second))
    assert deduped["m1"].usage.input_tokens == 5
    assert deduped["m1"].timestamp == "t2"


def test_aggregate_claude_usage_sums_token_categories() -> None:
    first = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
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
        1,
    )
    second = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "m2",
                "model": "claude-sonnet-4-6",
                "usage": {
                    "input_tokens": 20,
                    "cache_read_input_tokens": 4,
                    "cache_creation_input_tokens": 5,
                    "output_tokens": 6,
                },
            },
        },
        2,
    )
    assert first is not None
    assert second is not None

    snapshots = reduce_message_snapshots((first, second))

    aggregate = aggregate_claude_usage(snapshots)
    assert aggregate.input_tokens == 30
    assert aggregate.cached_input_tokens == 5
    assert aggregate.cache_creation_input_tokens == 7
    assert aggregate.output_tokens == 9
    assert aggregate.total_tokens == 51


def test_parse_claude_events_deduplicates_and_prices_single_model_sessions() -> None:
    usage = parse_claude_events(
        (
            {
                "sessionId": "claude-1",
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
        ),
        Path("/tmp/claude-a.jsonl"),
    )

    assert usage is not None
    assert usage["provider"] == "claude"
    assert usage["session_id"] == "claude-1"
    assert usage["model"] == "claude-sonnet-4-6"
    assert usage["pricing_model"] == "claude-sonnet-4-6"
    assert usage["input_tokens"] == 25
    assert usage["cached_input_tokens"] == 4
    assert usage["cache_creation_input_tokens"] == 6
    assert usage["output_tokens"] == 10
    assert usage["total_tokens"] == 45
    assert usage["timestamp"] == "2026-02-28T09:00:20Z"
    assert usage["session_total_cost_usd"] == pytest.approx(0.0002487)


def test_parse_claude_events_prices_mixed_models_per_message() -> None:
    usage = parse_claude_events(
        (
            {
                "sessionId": "mix",
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
                "sessionId": "mix",
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
        ),
        Path("/tmp/claude-mixed.jsonl"),
    )

    assert usage is not None
    assert usage["model"] == "mixed"
    assert usage["pricing_model"] == "mixed"
    assert usage["session_total_cost_usd"] == pytest.approx(0.00071125)


def test_parse_claude_events_unknown_models_keep_tokens_but_zero_out_costs() -> None:
    usage = parse_claude_events(
        (
            {
                "sessionId": "claude-unk",
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
            },
        ),
        Path("/tmp/claude-unknown.jsonl"),
    )

    assert usage is not None
    assert usage["pricing_model"] == ""
    assert usage["input_tokens"] == 10
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_claude_events_without_session_id_or_model_uses_empty_top_level_fields() -> None:
    usage = parse_claude_events(
        (
            {
                "timestamp": "2026-02-28T09:30:00Z",
                "message": {
                    "id": "u1",
                    "usage": {
                        "input_tokens": 1,
                        "cache_read_input_tokens": 2,
                        "cache_creation_input_tokens": 3,
                        "output_tokens": 4,
                    },
                },
            },
        ),
        Path("/tmp/claude-no-session-or-model.jsonl"),
    )

    assert usage is not None
    assert usage["session_id"] == ""
    assert usage["model"] == ""
    assert usage["pricing_model"] == ""
    assert usage["timestamp"] == "2026-02-28T09:30:00Z"


def test_parse_claude_events_returns_none_when_no_usage_bearing_messages_exist() -> None:
    assert parse_claude_events(({"sessionId": "empty", "message": "not-a-dict"},), Path("/tmp/no-usage.jsonl")) is None
