"""Unit tests for pure Codex parser reducer components."""

from pathlib import Path

import pytest

from token_auditor.core.codex import extract_codex_event_delta, finalize_codex_state, parse_codex_events, reduce_codex_state
from token_auditor.core.types import CodexState, TokenUsage


def test_extract_codex_event_delta_reads_session_and_turn_metadata() -> None:
    meta_delta = extract_codex_event_delta({"type": "session_meta", "payload": {"id": "session-1"}})
    context_delta = extract_codex_event_delta(
        {
            "type": "turn_context",
            "payload": {
                "model": "gpt-5.3-codex",
                "collaboration_mode": {"settings": {"reasoning_effort": "medium"}},
            },
        }
    )

    assert meta_delta.session_id == "session-1"
    assert context_delta.model == "gpt-5.3-codex"
    assert context_delta.reasoning_effort == "medium"


def test_extract_codex_event_delta_uses_effort_fallback_when_nested_setting_absent() -> None:
    delta = extract_codex_event_delta({"type": "turn_context", "payload": {"model": "gpt-5-codex", "effort": "high"}})
    assert delta.reasoning_effort == "high"


def test_extract_codex_event_delta_returns_none_effort_when_not_provided() -> None:
    delta = extract_codex_event_delta({"type": "turn_context", "payload": {"model": "gpt-5-codex"}})
    assert delta.reasoning_effort is None


def test_extract_codex_event_delta_ignores_non_token_count_event_msgs() -> None:
    delta = extract_codex_event_delta({"type": "event_msg", "payload": {"type": "tool_call"}})
    assert delta.usage is None


def test_extract_codex_event_delta_ignores_non_event_msg_types() -> None:
    assert extract_codex_event_delta({"type": "arbitrary"}).usage is None


def test_extract_codex_event_delta_ignores_empty_total_usage() -> None:
    delta = extract_codex_event_delta({"type": "event_msg", "payload": {"type": "token_count", "info": {}}})
    assert delta.usage is None


def test_reduce_codex_state_applies_only_present_delta_fields() -> None:
    initial = CodexState(session_id="a", model="gpt-5-codex", reasoning_effort="low", timestamp="t0")
    merged = reduce_codex_state(initial, extract_codex_event_delta({"type": "session_meta", "payload": {"id": "b"}}))

    assert merged.session_id == "b"
    assert merged.model == "gpt-5-codex"
    assert merged.reasoning_effort == "low"
    assert merged.timestamp == "t0"


def test_parse_codex_events_uses_last_token_count_and_pricing() -> None:
    events = (
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
    )

    usage = parse_codex_events(events, Path("/tmp/codex.jsonl"))

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
    assert usage["session_total_cost_usd"] == pytest.approx(0.000068)


def test_finalize_codex_state_recomputes_total_tokens_when_missing() -> None:
    state = CodexState(
        session_id="s",
        model="gpt-5-codex",
        reasoning_effort="",
        timestamp="t",
        usage=TokenUsage(input_tokens=2, cached_input_tokens=1, output_tokens=3, total_tokens=0),
    )

    usage = finalize_codex_state(state, Path("/tmp/codex-missing-total.jsonl"))
    assert usage is not None
    assert usage["total_tokens"] == 5


def test_parse_codex_events_returns_none_when_usage_absent() -> None:
    assert parse_codex_events(({"type": "session_meta", "payload": {"id": "x"}},), Path("/tmp/no-usage.jsonl")) is None


def test_parse_codex_events_sets_zero_cost_for_unknown_models() -> None:
    usage = parse_codex_events(
        (
            {"type": "session_meta", "payload": {"id": "unknown"}},
            {"type": "turn_context", "payload": {"model": "unknown-model", "effort": "xhigh"}},
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
        ),
        Path("/tmp/unknown-model.jsonl"),
    )

    assert usage is not None
    assert usage["pricing_model"] == ""
    assert usage["session_total_cost_usd"] == 0.0
