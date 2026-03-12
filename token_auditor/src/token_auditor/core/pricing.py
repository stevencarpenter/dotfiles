"""Pure pricing model resolution and cost arithmetic for token_auditor."""

from token_auditor.core.constants import LONG_CONTEXT_PRICING_USD_PER_1M, MODEL_PRICING_ALIASES, MODEL_PRICING_PREFIX_ALIASES, REASONING_EFFORT_MULTIPLIER, TOKEN_PRICING_USD_PER_1M
from token_auditor.core.types import CostBreakdown


def resolve_pricing_model(provider: str, model: str) -> str:
    """Resolve a raw model identifier to a canonical pricing table key."""
    normalized = model.strip().lower()
    if not normalized:
        return ""

    provider_pricing = TOKEN_PRICING_USD_PER_1M.get(provider, {})
    if normalized in provider_pricing:
        return normalized

    provider_aliases = MODEL_PRICING_ALIASES.get(provider, {})
    if normalized in provider_aliases:
        return provider_aliases[normalized]

    for prefix, target in MODEL_PRICING_PREFIX_ALIASES.get(provider, ()):  # pragma: no branch
        if normalized.startswith(prefix):
            return target

    if provider == "codex":
        for priced_model in provider_pricing:
            if normalized.startswith(f"{priced_model}-"):
                return priced_model

    return ""


def zero_costs() -> CostBreakdown:
    """Return a zero-valued cost breakdown preserving expected output keys."""
    return {
        "input_cost_usd": 0.0,
        "cached_input_cost_usd": 0.0,
        "cache_creation_input_cost_usd": 0.0,
        "output_cost_usd": 0.0,
        "reasoning_output_cost_usd": 0.0,
        "session_total_cost_usd": 0.0,
    }


def calculate_costs(
    provider: str,
    pricing_model: str,
    reasoning_effort: str,
    input_tokens: int,
    cached_input_tokens: int,
    cache_creation_input_tokens: int,
    output_tokens: int,
    reasoning_output_tokens: int,
    long_context: bool = False,
) -> CostBreakdown:
    """Compute session cost components using provider-specific billing rules."""
    provider_pricing = TOKEN_PRICING_USD_PER_1M.get(provider, {})
    if long_context and provider == "claude" and pricing_model in LONG_CONTEXT_PRICING_USD_PER_1M:
        pricing = LONG_CONTEXT_PRICING_USD_PER_1M[pricing_model]
    elif pricing_model not in provider_pricing:
        return zero_costs()
    else:
        pricing = provider_pricing[pricing_model]
    effort_multiplier = REASONING_EFFORT_MULTIPLIER.get(reasoning_effort, 1.0)

    billable_input_tokens = max(0, input_tokens - cached_input_tokens - cache_creation_input_tokens) if provider == "codex" else max(0, input_tokens)
    non_reasoning_output_tokens = max(0, output_tokens - reasoning_output_tokens)

    input_cost = billable_input_tokens * (pricing["input_tokens"] / 1_000_000)
    cached_input_cost = cached_input_tokens * (pricing["cached_input_tokens"] / 1_000_000)
    cache_creation_input_cost = cache_creation_input_tokens * (pricing["cache_creation_input_tokens"] / 1_000_000)
    output_cost = non_reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000)
    reasoning_output_cost = reasoning_output_tokens * (pricing["output_tokens"] / 1_000_000) * effort_multiplier
    session_total_cost = input_cost + cached_input_cost + cache_creation_input_cost + output_cost + reasoning_output_cost

    return {
        "input_cost_usd": input_cost,
        "cached_input_cost_usd": cached_input_cost,
        "cache_creation_input_cost_usd": cache_creation_input_cost,
        "output_cost_usd": output_cost,
        "reasoning_output_cost_usd": reasoning_output_cost,
        "session_total_cost_usd": session_total_cost,
    }
