"""Unit tests for pure rendering and formatting helpers."""

import json

from core.render import (
    decide_color_enabled,
    format_cost_rows,
    format_summary_rows,
    format_token_rows,
    format_tokens,
    format_usd,
    paint,
    render_json_audit,
    render_text_audit,
)

AUDIT = {
    "provider": "codex",
    "session_id": "abc",
    "session_file": "/tmp/s.jsonl",
    "timestamp": "2026-02-28T08:10:00Z",
    "model": "gpt-5.1-codex-mini",
    "pricing_model": "gpt-5.1-codex-mini",
    "reasoning_effort": "low",
    "input_tokens": 1042,
    "cached_input_tokens": 11,
    "cache_creation_input_tokens": 0,
    "output_tokens": 9,
    "reasoning_output_tokens": 3,
    "total_tokens": 1051,
    "input_cost_usd": 0.0004124,
    "cached_input_cost_usd": 0.00000044,
    "cache_creation_input_cost_usd": 0.0,
    "output_cost_usd": 0.0000192,
    "reasoning_output_cost_usd": 0.0000096,
    "session_total_cost_usd": 0.00044164,
    "cost_source": "estimated",
    "provider_billed_total": 0.0,
    "provider_billed_unit": "",
}


def test_decide_color_enabled_precedence_rules() -> None:
    assert decide_color_enabled("always", no_color=False, is_tty=False, term="dumb")
    assert not decide_color_enabled("never", no_color=False, is_tty=True, term="xterm-256color")
    assert not decide_color_enabled("auto", no_color=True, is_tty=True, term="xterm-256color")
    assert decide_color_enabled("auto", no_color=False, is_tty=True, term="xterm-256color")
    assert not decide_color_enabled("auto", no_color=False, is_tty=True, term="dumb")


def test_paint_formats_ansi_when_enabled() -> None:
    assert paint("hello", 108, enabled=False) == "hello"
    assert paint("hello", 108, enabled=True) == "\x1b[38;5;108mhello\x1b[0m"


def test_format_usd_and_tokens_produce_human_friendly_units() -> None:
    assert format_usd(0.1011496) == "$0.1011496"
    assert format_usd(0.0) == "$0"
    assert format_tokens(229402) == "229,402 tokens"


def test_row_formatters_generate_expected_labels_and_units() -> None:
    assert format_summary_rows(AUDIT)[0] == ("Session ID", "abc")
    assert format_summary_rows(AUDIT)[-1] == ("Cost Source", "estimated")
    assert format_token_rows(AUDIT)[0] == ("Input Tokens", "1,042 tokens")
    assert format_cost_rows(AUDIT)[-1] == ("Total Cost", "$0.00044164")


def test_format_cost_rows_appends_provider_billed_when_available() -> None:
    audit = {**AUDIT, "provider_billed_total": 4.0, "provider_billed_unit": "credits"}
    assert format_cost_rows(audit)[-1] == ("Provider Billed", "4 credits")


def test_render_text_audit_renders_all_sections_without_color() -> None:
    rendered = render_text_audit(AUDIT, use_color=False)

    assert "Codex Token Audit" in rendered
    assert "Token Usage" in rendered
    assert "Estimated Cost (USD)" in rendered
    assert "Input Tokens" in rendered and "1,042 tokens" in rendered
    assert "Total Cost" in rendered and "$0.00044164" in rendered


def test_render_json_audit_outputs_sorted_key_json() -> None:
    rendered = render_json_audit(AUDIT)
    payload = json.loads(rendered)

    assert payload["session_id"] == "abc"
    assert rendered.index('"cache_creation_input_cost_usd"') < rendered.index('"cached_input_cost_usd"')
