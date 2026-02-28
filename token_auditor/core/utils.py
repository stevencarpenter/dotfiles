"""Small pure utility helpers reused by token_auditor core modules."""

from typing import Any


def safe_int(value: Any) -> int:
    """Convert dynamic inputs to integers while tolerating malformed values."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
