"""Pure Codex session parsing pipeline built from reducer components."""

from collections.abc import Mapping
from functools import reduce
from pathlib import Path
from typing import cast

from core.pricing import calculate_costs, resolve_pricing_model
from core.types import AuditRecord, CodexDelta, CodexState, JsonEvent, TokenUsage
from core.utils import safe_int


def _mapping(value: object) -> Mapping[str, object]:
    """Return the input as a mapping when possible, otherwise an empty mapping."""
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _token_usage_from_mapping(total_usage: Mapping[str, object]) -> TokenUsage:
    """Convert a dynamic token-usage mapping into a typed immutable structure."""
    return TokenUsage(
        input_tokens=safe_int(total_usage.get("input_tokens", 0)),
        cached_input_tokens=safe_int(total_usage.get("cached_input_tokens", 0)),
        cache_creation_input_tokens=safe_int(total_usage.get("cache_creation_input_tokens", 0)),
        output_tokens=safe_int(total_usage.get("output_tokens", 0)),
        reasoning_output_tokens=safe_int(total_usage.get("reasoning_output_tokens", 0)),
        total_tokens=safe_int(total_usage.get("total_tokens", 0)),
    )


def _reasoning_effort(payload: Mapping[str, object]) -> str | None:
    """Extract reasoning effort in the same precedence order as the legacy parser."""
    collaboration_mode = _mapping(payload.get("collaboration_mode"))
    settings = _mapping(collaboration_mode.get("settings"))

    if "reasoning_effort" in settings:
        return str(settings.get("reasoning_effort"))
    if "effort" in payload:
        return str(payload.get("effort"))
    return None


def extract_codex_event_delta(event: JsonEvent) -> CodexDelta:
    """Extract a Codex reducer delta from a single decoded session event."""
    event_type = str(event.get("type", ""))

    if event_type == "session_meta":
        payload = _mapping(event.get("payload"))
        return CodexDelta(session_id=str(payload.get("id")) if "id" in payload else None)

    if event_type == "turn_context":
        payload = _mapping(event.get("payload"))
        model = str(payload.get("model")) if "model" in payload else None
        return CodexDelta(model=model, reasoning_effort=_reasoning_effort(payload))

    if event_type != "event_msg":
        return CodexDelta()

    payload = _mapping(event.get("payload"))
    if payload.get("type") != "token_count":
        return CodexDelta()

    info = _mapping(payload.get("info"))
    total_usage = _mapping(info.get("total_token_usage"))
    if not total_usage:
        return CodexDelta()

    timestamp = str(event.get("timestamp")) if "timestamp" in event else None
    return CodexDelta(usage=_token_usage_from_mapping(total_usage), timestamp=timestamp)


def reduce_codex_state(state: CodexState, delta: CodexDelta) -> CodexState:
    """Reduce one Codex delta into a new immutable Codex parsing state."""
    return CodexState(
        session_id=state.session_id if delta.session_id is None else delta.session_id,
        model=state.model if delta.model is None else delta.model,
        reasoning_effort=state.reasoning_effort if delta.reasoning_effort is None else delta.reasoning_effort,
        timestamp=state.timestamp if delta.timestamp is None else delta.timestamp,
        usage=state.usage if delta.usage is None else delta.usage,
    )


def _ensure_total_tokens(usage: TokenUsage) -> TokenUsage:
    """Backfill missing totals for transcripts that omit aggregate token counts."""
    if usage.total_tokens != 0:
        return usage
    return TokenUsage(
        input_tokens=usage.input_tokens,
        cached_input_tokens=usage.cached_input_tokens,
        cache_creation_input_tokens=usage.cache_creation_input_tokens,
        output_tokens=usage.output_tokens,
        reasoning_output_tokens=usage.reasoning_output_tokens,
        total_tokens=usage.input_tokens + usage.output_tokens,
    )


def finalize_codex_state(state: CodexState, session_file: Path) -> AuditRecord | None:
    """Transform a reduced Codex state into the normalized audit payload shape."""
    if state.usage is None:
        return None

    usage = _ensure_total_tokens(state.usage)
    pricing_model = resolve_pricing_model("codex", state.model)
    costs = calculate_costs(
        provider="codex",
        pricing_model=pricing_model,
        reasoning_effort=state.reasoning_effort,
        input_tokens=usage.input_tokens,
        cached_input_tokens=usage.cached_input_tokens,
        cache_creation_input_tokens=usage.cache_creation_input_tokens,
        output_tokens=usage.output_tokens,
        reasoning_output_tokens=usage.reasoning_output_tokens,
    )

    return {
        "provider": "codex",
        "session_id": state.session_id,
        "session_file": str(session_file),
        "timestamp": state.timestamp,
        "model": state.model,
        "reasoning_effort": state.reasoning_effort,
        "pricing_model": pricing_model,
        "input_tokens": usage.input_tokens,
        "cached_input_tokens": usage.cached_input_tokens,
        "cache_creation_input_tokens": usage.cache_creation_input_tokens,
        "output_tokens": usage.output_tokens,
        "reasoning_output_tokens": usage.reasoning_output_tokens,
        "total_tokens": usage.total_tokens,
        **costs,
    }


def parse_codex_events(events: tuple[JsonEvent, ...], session_file: Path) -> AuditRecord | None:
    """Parse decoded Codex events into an audit payload via a reducer fold."""
    deltas = (extract_codex_event_delta(event) for event in events)
    final_state = reduce(reduce_codex_state, deltas, CodexState())
    return finalize_codex_state(final_state, session_file)
