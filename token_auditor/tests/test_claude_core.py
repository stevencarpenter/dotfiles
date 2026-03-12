"""Unit tests for pure Claude parser components and aggregation rules."""

from pathlib import Path

import pytest

from token_auditor.core.claude import aggregate_claude_usage, compute_claude_costs, extract_claude_message_snapshot, parse_claude_events, reduce_message_snapshots


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
    assert usage["long_context_premium_usd"] == 0.0


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
    assert usage["long_context_premium_usd"] == 0.0


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


def test_compute_claude_costs_applies_long_context_for_messages_over_200k() -> None:
    """Single-model Opus session: one message under 200K, one over."""
    under = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
            "message": {
                "id": "m1",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 100,
                    "cache_read_input_tokens": 50_000,
                    "cache_creation_input_tokens": 10_000,
                    "output_tokens": 500,
                },
            },
        },
        1,
    )
    over = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "m2",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 1000,
                    "cache_read_input_tokens": 250_000,
                    "cache_creation_input_tokens": 50_000,
                    "output_tokens": 2000,
                },
            },
        },
        2,
    )
    assert under is not None
    assert over is not None
    deduped = reduce_message_snapshots((under, over))
    costs, premium = compute_claude_costs(deduped)

    # m1 (60,100 total input — standard): $0.1005
    # m2 (301,000 total input — long context): $0.96
    assert costs["session_total_cost_usd"] == pytest.approx(1.0605)

    # Premium = long_context_cost - standard_cost for m2 = $0.96 - $0.4925
    assert premium == pytest.approx(0.4675)


def test_compute_claude_costs_mixed_model_with_long_context() -> None:
    """Opus over 200K + Haiku under 200K — both model resolution and threshold detection."""
    opus = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
            "message": {
                "id": "o1",
                "model": "claude-opus-4-6",
                "usage": {
                    "input_tokens": 500,
                    "cache_read_input_tokens": 200_000,
                    "cache_creation_input_tokens": 100_000,
                    "output_tokens": 1000,
                },
            },
        },
        1,
    )
    haiku = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
            "message": {
                "id": "h1",
                "model": "claude-haiku-4-5",
                "usage": {
                    "input_tokens": 100,
                    "cache_read_input_tokens": 40_000,
                    "cache_creation_input_tokens": 10_000,
                    "output_tokens": 500,
                },
            },
        },
        2,
    )
    assert opus is not None
    assert haiku is not None
    deduped = reduce_message_snapshots((opus, haiku))
    costs, premium = compute_claude_costs(deduped)

    # Opus (300,500 input — long context): $1.4925
    # Haiku (50,100 input — standard, no long context tier): $0.0191
    assert costs["session_total_cost_usd"] == pytest.approx(1.5116)

    # Premium = opus_lc - opus_std = $1.4925 - $0.7525
    assert premium == pytest.approx(0.74)


def test_compute_claude_costs_single_model_matches_per_message_sum() -> None:
    """Per-message path produces same result as old aggregate path for under-200K sessions."""
    m1 = extract_claude_message_snapshot(
        {
            "timestamp": "t1",
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
        1,
    )
    m2 = extract_claude_message_snapshot(
        {
            "timestamp": "t2",
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
        2,
    )
    assert m1 is not None
    assert m2 is not None
    deduped = reduce_message_snapshots((m1, m2))
    costs, premium = compute_claude_costs(deduped)

    # Same expected value as test_parse_claude_events_deduplicates_and_prices_single_model_sessions
    assert costs["session_total_cost_usd"] == pytest.approx(0.0002487)
    assert premium == pytest.approx(0.0)


def test_parse_claude_events_includes_long_context_premium_field() -> None:
    usage = parse_claude_events(
        (
            {
                "sessionId": "lc-session",
                "timestamp": "2026-03-11T10:00:00Z",
                "message": {
                    "id": "lc1",
                    "model": "claude-opus-4-6",
                    "usage": {
                        "input_tokens": 100,
                        "cache_read_input_tokens": 250_000,
                        "cache_creation_input_tokens": 0,
                        "output_tokens": 500,
                    },
                },
            },
        ),
        Path("/tmp/claude-long-context.jsonl"),
    )

    assert usage is not None
    # 250,100 total input > 200K threshold
    # Long context Opus: input=100*10/M=0.001, cached=250000*1.0/M=0.25, output=500*37.5/M=0.01875
    assert usage["session_total_cost_usd"] == pytest.approx(0.26975)
    # Standard would be: input=0.0005, cached=0.125, output=0.0125 = 0.138
    assert usage["long_context_premium_usd"] == pytest.approx(0.13175)
