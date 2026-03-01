"""Unit tests for pure JSONL decoding helpers."""

from pathlib import Path

import pytest

from core.jsonl import decode_jsonl_lines
from core.types import SessionParseError


def test_decode_jsonl_lines_decodes_valid_input() -> None:
    lines = (
        '{"type":"session_meta","payload":{"id":"abc"}}\n',
        '{"type":"turn_context","payload":{"model":"gpt-5-codex"}}\n',
    )
    decoded = decode_jsonl_lines(lines, Path("/tmp/session.jsonl"))

    assert len(decoded) == 2
    assert decoded[0]["type"] == "session_meta"
    assert decoded[1]["type"] == "turn_context"


def test_decode_jsonl_lines_converts_non_mapping_records_to_empty_events() -> None:
    lines = ("[]\n", '"str"\n', "123\n")
    decoded = decode_jsonl_lines(lines, Path("/tmp/session.jsonl"))

    assert decoded == ({}, {}, {})


def test_decode_jsonl_lines_raises_line_aware_parse_error() -> None:
    lines = ('{"type":"ok"}\n', "{malformed\n")

    with pytest.raises(SessionParseError, match=r"Malformed JSON in session file: /tmp/session\.jsonl \(line 2\)"):
        decode_jsonl_lines(lines, Path("/tmp/session.jsonl"))
