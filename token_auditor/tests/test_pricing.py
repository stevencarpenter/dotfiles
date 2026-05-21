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


def test_resolve_pricing_model_handles_current_fleet_models() -> None:
    # New bare codex model IDs (no -codex suffix) resolve directly.
    assert resolve_pricing_model("codex", "gpt-5.5") == "gpt-5.5"
    assert resolve_pricing_model("codex", "gpt-5.4") == "gpt-5.4"
    assert resolve_pricing_model("codex", "gpt-5.4-mini") == "gpt-5.4-mini"
    # Date-suffixed variants resolve to the most specific (longest) matching prefix.
    assert resolve_pricing_model("codex", "gpt-5.4-mini-2026-03-17") == "gpt-5.4-mini"
    assert resolve_pricing_model("codex", "gpt-5.5-2026-04-01") == "gpt-5.5"
    # Bare Claude aliases (logged for some sessions) map to the current fleet.
    assert resolve_pricing_model("claude", "opus") == "claude-opus-4-7"
    assert resolve_pricing_model("claude", "sonnet") == "claude-sonnet-4-6"
    assert resolve_pricing_model("claude", "haiku") == "claude-haiku-4-5"


def test_resolve_pricing_model_returns_empty_for_unknown_or_blank_models() -> None:
    assert resolve_pricing_model("codex", "") == ""
    assert resolve_pricing_model("claude", "unknown-model") == ""


def test_calculate_costs_for_codex_subtracts_cached_and_cache_creation_from_input() -> None:
    costs = calculate_costs(
        provider="codex",
        pricing_model="gpt-5.3-codex",
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


def test_calculate_costs_for_gpt_5_5_uses_premium_codex_rates() -> None:
    costs = calculate_costs(
        provider="codex",
        pricing_model="gpt-5.5",
        input_tokens=1_000_000,
        cached_input_tokens=200_000,
        cache_creation_input_tokens=0,
        output_tokens=100_000,
        reasoning_output_tokens=40_000,
    )

    # gpt-5.5: input $5/M, cached $0.50/M, output $30/M. Billable input = 1M - 200K = 800K.
    assert costs["input_cost_usd"] == pytest.approx(4.0)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.1)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.0)
    assert costs["output_cost_usd"] == pytest.approx(1.8)
    assert costs["reasoning_output_cost_usd"] == pytest.approx(1.2)
    assert costs["session_total_cost_usd"] == pytest.approx(7.1)


def test_calculate_costs_for_gpt_5_4_family_uses_current_rates() -> None:
    full = calculate_costs(
        provider="codex",
        pricing_model="gpt-5.4",
        input_tokens=1_000_000,
        cached_input_tokens=0,
        cache_creation_input_tokens=0,
        output_tokens=1_000_000,
        reasoning_output_tokens=0,
    )
    # gpt-5.4: input $2.50/M, output $15/M.
    assert full["input_cost_usd"] == pytest.approx(2.5)
    assert full["output_cost_usd"] == pytest.approx(15.0)
    assert full["session_total_cost_usd"] == pytest.approx(17.5)

    mini = calculate_costs(
        provider="codex",
        pricing_model="gpt-5.4-mini",
        input_tokens=1_000_000,
        cached_input_tokens=100_000,
        cache_creation_input_tokens=0,
        output_tokens=200_000,
        reasoning_output_tokens=0,
    )
    # gpt-5.4-mini: input $0.75/M, cached $0.075/M, output $4.50/M. Billable input = 900K.
    assert mini["input_cost_usd"] == pytest.approx(0.675)
    assert mini["cached_input_cost_usd"] == pytest.approx(0.0075)
    assert mini["output_cost_usd"] == pytest.approx(0.9)
    assert mini["session_total_cost_usd"] == pytest.approx(1.5825)


def test_calculate_costs_returns_zero_breakdown_for_unknown_pricing_models() -> None:
    assert (
        calculate_costs(
            provider="claude",
            pricing_model="",
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


def test_calculate_costs_long_context_now_bills_flat_standard_rates() -> None:
    # As of Opus 4.6/4.7 and Sonnet 4.6, the full 1M context bills at standard rates,
    # so long_context=True yields the same costs as standard (no >200K premium).
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-opus-4-6",
        input_tokens=1000,
        cached_input_tokens=500_000,
        cache_creation_input_tokens=100_000,
        output_tokens=5000,
        reasoning_output_tokens=0,
        long_context=True,
    )

    # Standard Opus: input=$5/M, cached=$0.5/M, cache_creation=$6.25/M, output=$25/M
    assert costs["input_cost_usd"] == pytest.approx(0.005)
    assert costs["cached_input_cost_usd"] == pytest.approx(0.25)
    assert costs["cache_creation_input_cost_usd"] == pytest.approx(0.625)
    assert costs["output_cost_usd"] == pytest.approx(0.125)
    assert costs["session_total_cost_usd"] == pytest.approx(1.005)


def test_calculate_costs_long_context_falls_back_for_haiku() -> None:
    costs = calculate_costs(
        provider="claude",
        pricing_model="claude-haiku-4-5",
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
