"""Pure audit rendering and formatting for token_auditor."""

import json
from collections.abc import Sequence

from token_auditor.core.constants import EVERFOREST_GRADIENT_256, EVERFOREST_HEADER_COLOR_256, EVERFOREST_MUTED_COLOR_256, EVERFOREST_SECTION_COLOR_256
from token_auditor.core.types import AuditRecord


def decide_color_enabled(color_mode: str, no_color: bool, is_tty: bool, term: str) -> bool:
    """Decide whether ANSI color output should be enabled for this render pass."""
    normalized_mode = color_mode.strip().lower()
    if normalized_mode == "always":
        return True
    if normalized_mode == "never" or no_color:
        return False
    return is_tty and term.lower() != "dumb"


def paint(text: str, color_code_256: int, enabled: bool) -> str:
    """Wrap text with ANSI 256-color escapes when color output is enabled."""
    return f"\x1b[38;5;{color_code_256}m{text}\x1b[0m" if enabled else text


def format_usd(value: float) -> str:
    """Format USD values with comma separators and trimmed fractional tails."""
    return f"${value:,.9f}".rstrip("0").rstrip(".")


def format_tokens(value: int) -> str:
    """Format token counts with separators and a stable units suffix."""
    return f"{value:,} tokens"


def format_summary_rows(audit: AuditRecord) -> tuple[tuple[str, str], ...]:
    """Build summary display rows for provider/session metadata fields."""
    return (
        ("Session ID", str(audit.get("session_id", ""))),
        ("Session File", str(audit.get("session_file", ""))),
        ("Timestamp", str(audit.get("timestamp", ""))),
        ("Model", str(audit.get("model", ""))),
        ("Pricing Model", str(audit.get("pricing_model", ""))),
        ("Reasoning Effort", str(audit.get("reasoning_effort", "")) or "n/a"),
        ("Cost Source", str(audit.get("cost_source", "estimated"))),
    )


def format_token_rows(audit: AuditRecord) -> tuple[tuple[str, str], ...]:
    """Build token usage rows formatted for human-readable text output."""
    return (
        ("Input Tokens", format_tokens(int(audit["input_tokens"]))),
        ("Cached Input", format_tokens(int(audit["cached_input_tokens"]))),
        ("Cache Creation", format_tokens(int(audit["cache_creation_input_tokens"]))),
        ("Output Tokens", format_tokens(int(audit["output_tokens"]))),
        ("Reasoning Output", format_tokens(int(audit["reasoning_output_tokens"]))),
        ("Total Tokens", format_tokens(int(audit["total_tokens"]))),
    )


def format_cost_rows(audit: AuditRecord) -> tuple[tuple[str, str], ...]:
    """Build USD cost rows formatted for human-readable text output."""
    rows = [
        ("Input Cost", format_usd(float(audit["input_cost_usd"]))),
        ("Cached Input", format_usd(float(audit["cached_input_cost_usd"]))),
        ("Cache Creation", format_usd(float(audit["cache_creation_input_cost_usd"]))),
        ("Output Cost", format_usd(float(audit["output_cost_usd"]))),
        ("Reasoning Output", format_usd(float(audit["reasoning_output_cost_usd"]))),
    ]
    long_context_premium = float(audit.get("long_context_premium_usd", 0.0))
    if long_context_premium > 0:
        rows.append(("Long Ctx Premium", format_usd(long_context_premium)))
    rows.append(("Total Cost", format_usd(float(audit["session_total_cost_usd"]))))
    provider_billed_unit = str(audit.get("provider_billed_unit", ""))
    if provider_billed_unit:
        provider_billed_total = float(audit.get("provider_billed_total", 0.0))
        billed_value = format_usd(provider_billed_total) if provider_billed_unit == "usd" else f"{provider_billed_total:g} {provider_billed_unit}"
        rows.append(("Provider Billed", billed_value))
    return tuple(rows)


def _render_rows(rows: Sequence[tuple[str, str]], use_color: bool, color_offset: int = 0) -> list[str]:
    """Render aligned label/value rows with optional Everforest gradient labels."""
    rendered: list[str] = []
    for idx, (label, value) in enumerate(rows):
        label_color = EVERFOREST_GRADIENT_256[(idx + color_offset) % len(EVERFOREST_GRADIENT_256)]
        rendered.append(f"  {paint(f'{label:<20}', label_color, use_color)} {value}")
    return rendered


def render_text_audit(audit: AuditRecord, use_color: bool) -> str:
    """Render a full multiline text report for the provided audit payload."""
    provider = str(audit["provider"]).capitalize()
    title = f"{provider} Token Audit"

    lines: list[str] = [
        paint(title, EVERFOREST_HEADER_COLOR_256, use_color),
        paint("-" * len(title), EVERFOREST_MUTED_COLOR_256, use_color),
        *_render_rows(format_summary_rows(audit), use_color),
        "",
        paint("Token Usage", EVERFOREST_SECTION_COLOR_256, use_color),
        *_render_rows(format_token_rows(audit), use_color, color_offset=1),
        "",
        paint("Estimated Cost (USD)", EVERFOREST_SECTION_COLOR_256, use_color),
        *_render_rows(format_cost_rows(audit), use_color, color_offset=2),
    ]
    return "\n".join(lines)


def render_json_audit(audit: AuditRecord) -> str:
    """Render the audit payload as canonical sorted-key JSON."""
    return json.dumps(audit, sort_keys=True)
