"""Pure Amp thread parsing and selection helpers."""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from core.pricing import calculate_costs, resolve_pricing_model, zero_costs
from core.types import AuditRecord, CostBreakdown, JsonEvent
from core.utils import safe_float, safe_int


@dataclass(frozen=True)
class AmpThreadCandidate:
    """Thread candidate with payload and discovery metadata for selection."""

    path: Path
    mtime: float
    payload: object


@dataclass(frozen=True)
class AmpUsageSnapshot:
    """Normalized usage snapshot for one Amp assistant message."""

    message_id: str
    model: str
    timestamp: str
    input_tokens: int
    cached_input_tokens: int
    cache_creation_input_tokens: int
    output_tokens: int
    total_tokens: int
    credits: float
    has_credits: bool


def _mapping(value: object) -> Mapping[str, object]:
    """Return the input as a mapping when possible, otherwise an empty mapping."""
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _sequence(value: object) -> Sequence[object]:
    """Return the input as a sequence when possible, otherwise an empty sequence."""
    return cast(list[object], value) if isinstance(value, list) else ()


def _contains_cwd(value: object, cwd_text: str) -> bool:
    """Recursively search arbitrary payload values for a cwd substring."""
    if isinstance(value, str):
        return cwd_text in value
    if isinstance(value, dict):
        return any(_contains_cwd(item, cwd_text) for item in value.values())
    if isinstance(value, list):
        return any(_contains_cwd(item, cwd_text) for item in value)
    return False


def choose_amp_thread(candidates: tuple[AmpThreadCandidate, ...], cwd: Path) -> AmpThreadCandidate | None:
    """Choose thread by latest cwd match, falling back to latest global thread."""
    if not candidates:
        return None

    cwd_text = str(cwd)
    matching = tuple(candidate for candidate in candidates if _contains_cwd(candidate.payload, cwd_text))
    pool = matching or candidates
    return max(pool, key=lambda candidate: candidate.mtime)


def extract_amp_usage_snapshot(message: JsonEvent, line_number: int) -> AmpUsageSnapshot | None:
    """Extract one Amp assistant usage snapshot from a message payload."""
    if str(message.get("role", "")) != "assistant":
        return None

    usage = _mapping(message.get("usage"))
    if not usage:
        return None

    message_id = str(message.get("messageId") or f"line-{line_number}")
    total_input_tokens = safe_int(usage.get("totalInputTokens", 0))
    if total_input_tokens == 0:
        total_input_tokens = safe_int(usage.get("inputTokens", 0)) + safe_int(usage.get("cacheReadInputTokens", 0)) + safe_int(usage.get("cacheCreationInputTokens", 0))

    credits_value = usage.get("credits")
    has_credits = credits_value is not None

    return AmpUsageSnapshot(
        message_id=message_id,
        model=str(usage.get("model", "")),
        timestamp=str(usage.get("timestamp", "")),
        input_tokens=safe_int(usage.get("inputTokens", 0)),
        cached_input_tokens=safe_int(usage.get("cacheReadInputTokens", 0)),
        cache_creation_input_tokens=safe_int(usage.get("cacheCreationInputTokens", 0)),
        output_tokens=safe_int(usage.get("outputTokens", 0)),
        total_tokens=total_input_tokens + safe_int(usage.get("outputTokens", 0)),
        credits=safe_float(credits_value),
        has_credits=has_credits,
    )


def reduce_amp_usage_snapshots(snapshots: tuple[AmpUsageSnapshot, ...]) -> dict[str, AmpUsageSnapshot]:
    """Deduplicate snapshots by message id while keeping the latest occurrence."""
    deduped: dict[str, AmpUsageSnapshot] = {}
    for snapshot in snapshots:
        deduped[snapshot.message_id] = snapshot
    return deduped


def compute_amp_costs(deduped_snapshots: Mapping[str, AmpUsageSnapshot], pricing_model: str) -> CostBreakdown:
    """Compute estimated USD costs for Amp transcripts using model pricing aliases."""
    if pricing_model != "mixed":
        return calculate_costs(
            provider="amp",
            pricing_model=pricing_model,
            reasoning_effort="",
            input_tokens=sum(snapshot.input_tokens for snapshot in deduped_snapshots.values()),
            cached_input_tokens=sum(snapshot.cached_input_tokens for snapshot in deduped_snapshots.values()),
            cache_creation_input_tokens=sum(snapshot.cache_creation_input_tokens for snapshot in deduped_snapshots.values()),
            output_tokens=sum(snapshot.output_tokens for snapshot in deduped_snapshots.values()),
            reasoning_output_tokens=0,
        )

    accumulated = zero_costs()
    for snapshot in deduped_snapshots.values():
        message_pricing_model = resolve_pricing_model("amp", snapshot.model)
        message_costs = calculate_costs(
            provider="amp",
            pricing_model=message_pricing_model,
            reasoning_effort="",
            input_tokens=snapshot.input_tokens,
            cached_input_tokens=snapshot.cached_input_tokens,
            cache_creation_input_tokens=snapshot.cache_creation_input_tokens,
            output_tokens=snapshot.output_tokens,
            reasoning_output_tokens=0,
        )
        for key, value in message_costs.items():
            accumulated[key] += value
    return accumulated


def parse_amp_thread_payload(payload: JsonEvent, session_file: Path) -> AuditRecord | None:
    """Parse one Amp thread payload into the shared audit payload shape."""
    snapshots = tuple(
        filter(
            None,
            (extract_amp_usage_snapshot(cast(JsonEvent, message), line_number) for line_number, message in enumerate(_sequence(payload.get("messages")), start=1)),
        )
    )
    deduped_snapshots = reduce_amp_usage_snapshots(snapshots)
    if not deduped_snapshots:
        return None

    models = sorted({snapshot.model for snapshot in deduped_snapshots.values() if snapshot.model})
    model = models[0] if len(models) == 1 else ("mixed" if len(models) > 1 else "")
    pricing_model = resolve_pricing_model("amp", model) if len(models) == 1 else ("mixed" if len(models) > 1 else "")
    costs = compute_amp_costs(deduped_snapshots, pricing_model)

    has_credits = any(snapshot.has_credits for snapshot in deduped_snapshots.values())
    provider_billed_total = sum(snapshot.credits for snapshot in deduped_snapshots.values() if snapshot.has_credits)
    timestamps = sorted(snapshot.timestamp for snapshot in deduped_snapshots.values() if snapshot.timestamp)
    timestamp = timestamps[-1] if timestamps else ""

    return {
        "provider": "amp",
        "session_id": str(payload.get("id", "")),
        "session_file": str(session_file),
        "timestamp": timestamp,
        "model": model,
        "reasoning_effort": "",
        "pricing_model": pricing_model,
        "input_tokens": sum(snapshot.input_tokens for snapshot in deduped_snapshots.values()),
        "cached_input_tokens": sum(snapshot.cached_input_tokens for snapshot in deduped_snapshots.values()),
        "cache_creation_input_tokens": sum(snapshot.cache_creation_input_tokens for snapshot in deduped_snapshots.values()),
        "output_tokens": sum(snapshot.output_tokens for snapshot in deduped_snapshots.values()),
        "reasoning_output_tokens": 0,
        "total_tokens": sum(snapshot.total_tokens for snapshot in deduped_snapshots.values()),
        "cost_source": "hybrid" if has_credits else "estimated",
        "provider_billed_total": provider_billed_total if has_credits else 0.0,
        "provider_billed_unit": "credits" if has_credits else "",
        **costs,
    }
