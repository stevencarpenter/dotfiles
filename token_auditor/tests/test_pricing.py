"""Unit tests for pure pricing model resolution and cost arithmetic."""

import pytest

from token_auditor.core.pricing import calculate_costs, resolve_pricing_model, zero_costs
from token_auditor.core.utils import safe_int


def test_resolve_pricing_model_matches_direct_table_entries() -> None:
    assert resolve_pricing_model("codex", "gpt-5.3-codex") == "gpt-5.3-codex"
    assert resolve_pricing_model("claude", "claude-sonnet-4-6") == "claude-sonnet-4-6"


def test_resolve_pricing_model_applies_alias_and_prefix_rules() -> None:
    assert resolve_pricing_model("codex", "gpt-5.3-codex-mini") == "gpt-5.2-codex-mini"
    assert resolve_pricing_model("codex", "gpt-5-codex-2026-02-14") == "gpt-5-codex"
    assert resolve_pricing_model("claude", "claude-sonnet-4-5-20250929") == "claude-sonnet-4-6"


def test_resolve_pricing_model_returns_empty_for_unknown_or_blank_models() -> None:
    assert resolve_pricing_model("codex", "") == ""
    assert resolve_pricing_model("claude", "unknown-model") == ""


def test_calculate_costs_for_codex_subtracts_cached_and_cache_creation_from_input() -> None:
    costs = calculate_costs(
        provider="codex",
        pricing_model="gpt-5.3-codex",
        reasoning_effort="xhigh",
        input_tokens=4045228,
        cached_input_tokens=3780608,
        cache_creation_input_tokens=0,
        output_tokens=24495,
        reasoning_output_tokens=12415,
    )

    assert costs["input_cost_usd"] == pytest.approx(0.463085)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.6616064)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.0)
    assert costs["output_cost_usd"] == pytest.approx(0.16912)
    assert costs["reasoning_output_cost_usd"] == pytest.approx(0.17381)
    assert costs["session_total_cost_usd"] == pytest.approx(1.4676214)


def test_calculate_costs_for_claude_uses_direct_input_tokens() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-haiku-4-5",
        reasoning_effort="",
        input_tokens=36,
        cached_input_tokens=165811,
        cache_creation_input_tokens=62198,
        output_tokens=1357,
        reasoning_output_tokens=0,
    )

    assert costs["input_cost_usd"] == pytest.approx(0.000036)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.0165811)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.0777475)
    assert costs["output_cost_usd"] == pytest.approx(0.006785)
    assert costs["reasoning_output_cost_usd"] == pytest.approx(0.0)
    assert costs["session_total_cost_usd"] == pytest.approx(0.1011496)


def test_calculate_costs_returns_zero_breakdown_for_unknown_pricing_models() -> None:
    assert (
        calculate_costs(
            provider="claude",
            pricing_model="",
            reasoning_effort="",
            input_tokens=1,
            cached_input_tokens=2,
            cache_creation_input_tokens=3,
            output_tokens=4,
            reasoning_output_tokens=0,
        )
        == zero_costs()
    )


def test_safe_int_handles_invalid_inputs() -> None:
    assert safe_int("42") == 42
    assert safe_int(object()) == 0


def test_calculate_costs_long_context_applies_premium_rates() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-opus-4-6",
        reasoning_effort="",
        input_tokens=1000,
        cached_input_tokens=500_000,
        cache_creation_input_tokens=100_000,
        output_tokens=5000,
        reasoning_output_tokens=0,
        long_context=True,
    )

    # Long context Opus: input=$10/M, cached=$1/M, cache_creation=$12.5/M, output=$37.5/M
    assert costs["input_cost_usd"] == pytest.approx(0.01)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.50)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(1.25)
    assert costs["output_cost_usd"] == pytest.approx(0.1875)
    assert costs["session_total_cost_usd"] == pytest.approx(1.9475)


def test_calculate_costs_long_context_falls_back_for_haiku() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-haiku-4-5",
        reasoning_effort="",
        input_tokens=36,
        cached_input_tokens=165811,
        cache_creation_input_tokens=62198,
        output_tokens=1357,
        reasoning_output_tokens=0,
        long_context=True,
    )

    # Haiku has no long context tier — falls back to standard rates
    assert costs["input_cost_usd"] == pytest.approx(0.000036)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.0165811)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.0777475)
    assert costs["output_cost_usd"] == pytest.approx(0.006785)
    assert costs["session_total_cost_usd"] == pytest.approx(0.1011496)


def test_calculate_costs_long_context_false_uses_standard_rates() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-opus-4-6",
        reasoning_effort="",
        input_tokens=1000,
        cached_input_tokens=500_000,
        cache_creation_input_tokens=100_000,
        output_tokens=5000,
        reasoning_output_tokens=0,
        long_context=False,
    )

    # Standard Opus: input=$5/M, cached=$0.5/M, cache_creation=$6.25/M, output=$25/M
    assert costs["input_cost_usd"] == pytest.approx(0.005)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.25)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.625)
    assert costs["output_cost_usd"] == pytest.approx(0.125)
    assert costs["session_total_cost_usd"] == pytest.approx(1.005)
