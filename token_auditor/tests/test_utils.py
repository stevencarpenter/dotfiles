"""Unit tests for utility coercion helpers."""

from core.utils import safe_float, safe_int


def test_safe_int_returns_zero_for_malformed_values() -> None:
    assert safe_int("abc") == 0


def test_safe_float_returns_zero_for_malformed_values() -> None:
    assert safe_float("abc") == 0.0
