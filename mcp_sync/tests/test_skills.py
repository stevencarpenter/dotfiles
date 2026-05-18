"""Tests for the skill synchronization module."""

from __future__ import annotations

import pytest

from mcp_sync.skills import parse_duration


def test_parse_duration_hours():
    assert parse_duration("168h") == 604800


def test_parse_duration_days():
    assert parse_duration("7d") == 604800


def test_parse_duration_minutes_and_seconds():
    assert parse_duration("30m") == 1800
    assert parse_duration("45s") == 45


def test_parse_duration_rejects_garbage():
    with pytest.raises(ValueError, match="Invalid duration"):
        parse_duration("soon")
