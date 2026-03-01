"""Unit tests for side-effectful logging configuration adapter."""

import logging
import sys

from token_auditor._logging import LOG_FORMAT, configure


def test_configure_calls_basic_config_with_expected_parameters(monkeypatch) -> None:
    captured: dict[str, object] = {}

    def fake_basic_config(**kwargs: object) -> None:
        captured.update(kwargs)

    monkeypatch.setattr(logging, "basicConfig", fake_basic_config)
    configure("INFO")

    assert captured["level"] == "INFO"
    assert captured["format"] == LOG_FORMAT
    assert captured["stream"] is sys.stderr
