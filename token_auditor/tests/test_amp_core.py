"""Unit tests for pure Amp parser components and thread selection rules."""

from pathlib import Path

import pytest

from core.amp import AmpThreadCandidate, choose_amp_thread, parse_amp_thread_payload


def test_choose_amp_thread_prefers_latest_cwd_match() -> None:
    candidates = (
        AmpThreadCandidate(
            path=Path("/tmp/old-match.json"),
            mtime=100.0,
            payload={"messages": [{"content": [{"type": "text", "text": "/workspace/repo"}]}]},
        ),
        AmpThreadCandidate(
            path=Path("/tmp/new-non-match.json"),
            mtime=200.0,
            payload={"messages": [{"content": [{"type": "text", "text": "/other/repo"}]}]},
        ),
        AmpThreadCandidate(
            path=Path("/tmp/new-match.json"),
            mtime=150.0,
            payload={"messages": [{"content": [{"type": "text", "text": "/workspace/repo/service"}]}]},
        ),
    )

    selected = choose_amp_thread(candidates, Path("/workspace/repo"))
    assert selected is not None
    assert selected.path == Path("/tmp/new-match.json")


def test_choose_amp_thread_falls_back_to_latest_when_no_match() -> None:
    candidates = (
        AmpThreadCandidate(path=Path("/tmp/older.json"), mtime=100.0, payload={"messages": []}),
        AmpThreadCandidate(path=Path("/tmp/latest.json"), mtime=200.0, payload={"messages": []}),
    )

    selected = choose_amp_thread(candidates, Path("/workspace/repo"))
    assert selected is not None
    assert selected.path == Path("/tmp/latest.json")


def test_choose_amp_thread_handles_non_container_payload_values() -> None:
    candidates = (
        AmpThreadCandidate(path=Path("/tmp/a.json"), mtime=1.0, payload=1),
        AmpThreadCandidate(path=Path("/tmp/b.json"), mtime=2.0, payload=2),
    )

    selected = choose_amp_thread(candidates, Path("/workspace/repo"))
    assert selected is not None
    assert selected.path == Path("/tmp/b.json")


def test_choose_amp_thread_returns_none_for_empty_candidates() -> None:
    assert choose_amp_thread((), Path("/workspace/repo")) is None


def test_parse_amp_thread_payload_hybrid_costs_when_credits_exist() -> None:
    payload = {
        "id": "T-hybrid",
        "messages": [
            {
                "role": "assistant",
                "messageId": 1,
                "usage": {
                    "model": "claude-haiku-4-5-20251001",
                    "inputTokens": 100,
                    "outputTokens": 5,
                    "cacheReadInputTokens": 20,
                    "cacheCreationInputTokens": 10,
                    "totalInputTokens": 130,
                    "credits": 1.5,
                },
            },
            {
                "role": "assistant",
                "messageId": 2,
                "usage": {
                    "model": "claude-haiku-4-5-20251001",
                    "inputTokens": 50,
                    "outputTokens": 5,
                    "cacheReadInputTokens": 0,
                    "cacheCreationInputTokens": 0,
                    "totalInputTokens": 50,
                    "credits": 2.5,
                },
            },
        ],
    }

    usage = parse_amp_thread_payload(payload, Path("/tmp/thread.json"))

    assert usage is not None
    assert usage["provider"] == "amp"
    assert usage["session_id"] == "T-hybrid"
    assert usage["model"] == "claude-haiku-4-5-20251001"
    assert usage["pricing_model"] == "claude-haiku-4-5"
    assert usage["input_tokens"] == 150
    assert usage["cached_input_tokens"] == 20
    assert usage["cache_creation_input_tokens"] == 10
    assert usage["output_tokens"] == 10
    assert usage["total_tokens"] == 190
    assert usage["cost_source"] == "hybrid"
    assert usage["provider_billed_total"] == pytest.approx(4.0)
    assert usage["provider_billed_unit"] == "credits"
    assert usage["session_total_cost_usd"] == pytest.approx(0.0002145)


def test_parse_amp_thread_payload_estimated_only_when_credits_absent() -> None:
    payload = {
        "id": "T-estimated",
        "messages": [
            {
                "role": "assistant",
                "messageId": 1,
                "usage": {
                    "model": "unknown-model",
                    "inputTokens": 10,
                    "outputTokens": 3,
                    "cacheReadInputTokens": 0,
                    "cacheCreationInputTokens": 0,
                    "totalInputTokens": 10,
                },
            },
        ],
    }

    usage = parse_amp_thread_payload(payload, Path("/tmp/thread.json"))

    assert usage is not None
    assert usage["pricing_model"] == ""
    assert usage["cost_source"] == "estimated"
    assert usage["provider_billed_total"] == 0.0
    assert usage["provider_billed_unit"] == ""
    assert usage["session_total_cost_usd"] == 0.0


def test_parse_amp_thread_payload_returns_none_without_usage_messages() -> None:
    usage = parse_amp_thread_payload({"id": "T-none", "messages": [{"role": "user"}]}, Path("/tmp/thread.json"))
    assert usage is None


def test_parse_amp_thread_payload_returns_none_for_assistant_messages_with_invalid_usage() -> None:
    usage = parse_amp_thread_payload(
        {
            "id": "T-invalid",
            "messages": [
                {"role": "assistant", "messageId": 1, "usage": "not-a-mapping"},
                {"role": "assistant", "messageId": 2},
            ],
        },
        Path("/tmp/thread.json"),
    )
    assert usage is None


def test_parse_amp_thread_payload_uses_fallback_total_input_and_mixed_costing() -> None:
    payload = {
        "id": "T-mixed",
        "messages": [
            {
                "role": "assistant",
                "messageId": 1,
                "usage": {
                    "model": "claude-sonnet-4-6",
                    "timestamp": "2026-02-28T09:00:00Z",
                    "inputTokens": 20,
                    "outputTokens": 10,
                    "cacheReadInputTokens": 5,
                    "cacheCreationInputTokens": 3,
                },
            },
            {
                "role": "assistant",
                "messageId": 2,
                "usage": {
                    "model": "claude-haiku-4-5-20251001",
                    "timestamp": "2026-02-28T09:01:00Z",
                    "inputTokens": 50,
                    "outputTokens": 5,
                    "cacheReadInputTokens": 0,
                    "cacheCreationInputTokens": 0,
                    "totalInputTokens": 50,
                },
            },
        ],
    }

    usage = parse_amp_thread_payload(payload, Path("/tmp/thread.json"))

    assert usage is not None
    assert usage["model"] == "mixed"
    assert usage["pricing_model"] == "mixed"
    assert usage["total_tokens"] == 93
    assert usage["timestamp"] == "2026-02-28T09:01:00Z"
    assert usage["session_total_cost_usd"] == pytest.approx(0.00029775)
