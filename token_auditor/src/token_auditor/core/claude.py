"""Pure Claude session parsing pipeline with deterministic message deduplication."""

from collections.abc import Mapping
from pathlib import Path
from typing import cast

from token_auditor.core.constants import LONG_CONTEXT_INPUT_THRESHOLD
from token_auditor.core.pricing import calculate_costs, resolve_pricing_model, zero_costs
from token_auditor.core.types import AuditRecord, ClaudeMessageSnapshot, CostBreakdown, JsonEvent, TokenUsage
from token_auditor.core.utils import safe_int


def _mapping(value: object) -> Mapping[str, object]:
    """Return the input as a mapping when possible, otherwise an empty mapping."""
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def extract_claude_message_snapshot(event: JsonEvent, line_number: int) -> ClaudeMessageSnapshot | None:
    """Build a normalized message usage snapshot from one Claude JSONL event."""
    message = _mapping(event.get("message"))
    if not message:
        return None

    usage = _mapping(message.get("usage"))
    if not usage:
        return None

    message_id = str(message.get("id") or f"line-{line_number}")
    return ClaudeMessageSnapshot(
        message_id=message_id,
        model=str(message.get("model", "")),
        timestamp=str(event.get("timestamp", "")),
        usage=TokenUsage(
            input_tokens=safe_int(usage.get("input_tokens", 0)),
            cached_input_tokens=safe_int(usage.get("cache_read_input_tokens", 0)),
            cache_creation_input_tokens=safe_int(usage.get("cache_creation_input_tokens", 0)),
            output_tokens=safe_int(usage.get("output_tokens", 0)),
            reasoning_output_tokens=0,
            total_tokens=0,
        ),
    )


def reduce_message_snapshots(snapshots: tuple[ClaudeMessageSnapshot, ...]) -> dict[str, ClaudeMessageSnapshot]:
    """Deduplicate snapshots by message id while keeping the latest occurrence."""
    deduped: dict[str, ClaudeMessageSnapshot] = {}
    for snapshot in snapshots:
        deduped[snapshot.message_id] = snapshot
    return deduped


def aggregate_claude_usage(deduped_snapshots: Mapping[str, ClaudeMessageSnapshot]) -> TokenUsage:
    """Aggregate Claude usage totals across deduplicated message snapshots."""
    input_tokens = sum(snapshot.usage.input_tokens for snapshot in deduped_snapshots.values())
    cached_input_tokens = sum(snapshot.usage.cached_input_tokens for snapshot in deduped_snapshots.values())
    cache_creation_input_tokens = sum(snapshot.usage.cache_creation_input_tokens for snapshot in deduped_snapshots.values())
    output_tokens = sum(snapshot.usage.output_tokens for snapshot in deduped_snapshots.values())

    return TokenUsage(
        input_tokens=input_tokens,
        cached_input_tokens=cached_input_tokens,
        cache_creation_input_tokens=cache_creation_input_tokens,
        output_tokens=output_tokens,
        reasoning_output_tokens=0,
        total_tokens=input_tokens + cached_input_tokens + cache_creation_input_tokens + output_tokens,
    )


def _model_metadata(deduped_snapshots: Mapping[str, ClaudeMessageSnapshot]) -> tuple[str, str]:
    """Determine top-level model metadata for single-model and mixed sessions."""
    models = sorted({snapshot.model for snapshot in deduped_snapshots.values() if snapshot.model})
    if len(models) == 1:
        model = models[0]
        return model, resolve_pricing_model("claude", model)
    if len(models) > 1:
        return "mixed", "mixed"
    return "", ""


def _latest_timestamp(deduped_snapshots: Mapping[str, ClaudeMessageSnapshot]) -> str:
    """Return the latest snapshot timestamp using lexical ISO ordering."""
    timestamps = sorted(snapshot.timestamp for snapshot in deduped_snapshots.values())
    return timestamps[-1] if timestamps else ""


def compute_claude_costs(
    deduped_snapshots: Mapping[str, ClaudeMessageSnapshot],
) -> tuple[CostBreakdown, float]:
    """Compute Claude costs per-message with long context threshold detection."""
    accumulated = zero_costs()
    long_context_premium = 0.0

    for snapshot in deduped_snapshots.values():
        message_pricing_model = resolve_pricing_model("claude", snapshot.model)
        total_input = snapshot.usage.input_tokens + snapshot.usage.cached_input_tokens + snapshot.usage.cache_creation_input_tokens
        is_long_context = total_input > LONG_CONTEXT_INPUT_THRESHOLD

        message_costs = calculate_costs(
            provider="claude",
            pricing_model=message_pricing_model,
            reasoning_effort="",
            input_tokens=snapshot.usage.input_tokens,
            cached_input_tokens=snapshot.usage.cached_input_tokens,
            cache_creation_input_tokens=snapshot.usage.cache_creation_input_tokens,
            output_tokens=snapshot.usage.output_tokens,
            reasoning_output_tokens=0,
            long_context=is_long_context,
        )
        for key, value in message_costs.items():
            accumulated[key] += value

        if is_long_context:
            standard_costs = calculate_costs(
                provider="claude",
                pricing_model=message_pricing_model,
                reasoning_effort="",
                input_tokens=snapshot.usage.input_tokens,
                cached_input_tokens=snapshot.usage.cached_input_tokens,
                cache_creation_input_tokens=snapshot.usage.cache_creation_input_tokens,
                output_tokens=snapshot.usage.output_tokens,
                reasoning_output_tokens=0,
                long_context=False,
            )
            long_context_premium += message_costs["session_total_cost_usd"] - standard_costs["session_total_cost_usd"]

    return accumulated, long_context_premium


def finalize_claude_audit(
    session_id: str,
    deduped_snapshots: Mapping[str, ClaudeMessageSnapshot],
    session_file: Path,
) -> AuditRecord:
    """Build the normalized Claude audit payload from deduped snapshots."""
    aggregate = aggregate_claude_usage(deduped_snapshots)
    model, pricing_model = _model_metadata(deduped_snapshots)
    costs, long_context_premium = compute_claude_costs(deduped_snapshots)

    return {
        "provider": "claude",
        "session_id": session_id,
        "session_file": str(session_file),
        "timestamp": _latest_timestamp(deduped_snapshots),
        "model": model,
        "reasoning_effort": "",
        "pricing_model": pricing_model,
        "input_tokens": aggregate.input_tokens,
        "cached_input_tokens": aggregate.cached_input_tokens,
        "cache_creation_input_tokens": aggregate.cache_creation_input_tokens,
        "output_tokens": aggregate.output_tokens,
        "reasoning_output_tokens": 0,
        "total_tokens": aggregate.total_tokens,
        "cost_source": "estimated",
        "provider_billed_total": 0.0,
        "provider_billed_unit": "",
        **costs,
        "long_context_premium_usd": long_context_premium,
    }


def parse_claude_events(events: tuple[JsonEvent, ...], session_file: Path) -> AuditRecord | None:
    """Parse decoded Claude events into an audit payload via pure transforms."""
    session_id = ""
    snapshots: list[ClaudeMessageSnapshot] = []

    for line_number, event in enumerate(events, start=1):
        if "sessionId" in event:
            session_id = str(event.get("sessionId"))
        snapshot = extract_claude_message_snapshot(event, line_number)
        if snapshot is not None:
            snapshots.append(snapshot)

    deduped_snapshots = reduce_message_snapshots(tuple(snapshots))
    if not deduped_snapshots:
        return None

    return finalize_claude_audit(session_id, deduped_snapshots, session_file)
