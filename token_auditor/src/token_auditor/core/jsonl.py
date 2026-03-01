"""Pure JSONL decoding utilities for token_auditor."""

import json
from collections.abc import Sequence
from pathlib import Path

from token_auditor.core.types import JsonEvent, SessionParseError


def decode_jsonl_lines(lines: Sequence[str], session_file: Path) -> tuple[JsonEvent, ...]:
    """Decode JSONL content into events with stable parse error messaging."""
    decoded: list[JsonEvent] = []
    for line_number, line in enumerate(lines, start=1):
        try:
            raw_event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SessionParseError(f"Malformed JSON in session file: {session_file} (line {line_number})") from exc
        decoded.append(raw_event if isinstance(raw_event, dict) else {})
    return tuple(decoded)
