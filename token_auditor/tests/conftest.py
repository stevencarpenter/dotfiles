"""Shared pytest helpers for token_auditor domain test modules."""

import json
from pathlib import Path
from typing import Any


def write_session_file(path: Path, lines: list[dict[str, Any]]) -> None:
    """Write JSONL session fixtures with deterministic newline handling."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{json.dumps(line)}\n" for line in lines), encoding="utf-8")
